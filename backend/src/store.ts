import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { APIError, type AssetStatus, type GenerationRequest, type Job, type JobKind, type ReadingStatus, type StoryRecord } from "./types";

interface StoryRow { document: string; reading_status: ReadingStatus | null; reading_revision: number | null }
const storySelect = "SELECT s.document, r.status AS reading_status, r.revision AS reading_revision FROM stories s LEFT JOIN reading_states r ON r.story_id=s.id";

interface JobRow {
  id: string; kind: JobKind; story_id: string; status: Job["status"]; payload: string;
  created_at: string; updated_at: string; error: string | null; attempts: number;
  idempotency_key: string | null; fingerprint: string; lease_owner: string | null; lease_until: number | null;
}
export interface ClaimedJob extends Job { leaseOwner: string }

export class Store {
  readonly db: Database;
  constructor(readonly directory: string) {
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.db = new Database(join(directory, "fablo.sqlite"), { create: true, strict: true });
    this.db.run("PRAGMA journal_mode=WAL");
    this.db.run("PRAGMA busy_timeout=5000");
    this.db.run("PRAGMA synchronous=FULL");
    this.db.run(`
      CREATE TABLE IF NOT EXISTS stories (id TEXT PRIMARY KEY, document TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS reading_states (story_id TEXT PRIMARY KEY, status TEXT NOT NULL CHECK(status IN ('unread','reading','read')), revision INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS jobs (
        id TEXT PRIMARY KEY, kind TEXT NOT NULL, story_id TEXT NOT NULL, status TEXT NOT NULL,
        payload TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        error TEXT, attempts INTEGER NOT NULL DEFAULT 0, idempotency_key TEXT UNIQUE,
        fingerprint TEXT NOT NULL, active_key TEXT NOT NULL, lease_owner TEXT, lease_until INTEGER
      );
      CREATE UNIQUE INDEX IF NOT EXISTS jobs_active ON jobs(active_key) WHERE status IN ('queued', 'running');
      CREATE INDEX IF NOT EXISTS jobs_pending ON jobs(status, created_at);
      CREATE INDEX IF NOT EXISTS jobs_story ON jobs(story_id,kind,created_at);
      CREATE TABLE IF NOT EXISTS sessions (hash TEXT PRIMARY KEY, expires_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
      INSERT OR IGNORE INTO settings VALUES ('revision', 0);
      CREATE TRIGGER IF NOT EXISTS story_insert_revision AFTER INSERT ON stories BEGIN UPDATE settings SET value=value+1 WHERE key='revision'; END;
      CREATE TRIGGER IF NOT EXISTS story_update_revision AFTER UPDATE ON stories BEGIN UPDATE settings SET value=value+1 WHERE key='revision'; END;
      CREATE TRIGGER IF NOT EXISTS story_delete_revision AFTER DELETE ON stories BEGIN UPDATE settings SET value=value+1 WHERE key='revision'; END;
    `);
    // Recover full generation metadata for stories created before it was stored on the record.
    this.db.query(`
      UPDATE stories SET document=json_set(document,
        '$.generationRequest', json((SELECT json_extract(payload,'$.request') FROM jobs
          WHERE story_id=stories.id AND kind='story' AND json_type(payload,'$.request')='object'
          ORDER BY created_at LIMIT 1)), '$.updatedAt', ?1), updated_at=?1
      WHERE coalesce(json_type(document,'$.generationRequest'),'null')='null' AND EXISTS (
        SELECT 1 FROM jobs WHERE story_id=stories.id AND kind='story' AND json_type(payload,'$.request')='object'
      )
    `).run(new Date().toISOString());
  }
  close() { this.db.close(); }
  private story(row: StoryRow): StoryRecord {
    return { ...JSON.parse(row.document), readingStatus: row.reading_status ?? "unread", readingStatusRevision: row.reading_revision ?? 0 };
  }
  getStory(id: string): StoryRecord | null {
    const row = this.db.query<StoryRow, [string]>(`${storySelect} WHERE s.id=?`).get(id);
    return row ? this.story(row) : null;
  }
  listStories(limit = 50, offset = 0): StoryRecord[] {
    return this.db.query<StoryRow, [number, number]>(`${storySelect} ORDER BY s.created_at DESC, s.id LIMIT ? OFFSET ?`).all(limit, offset).map(r => this.story(r));
  }
  countStories(): number { return this.db.query<{ count: number }, []>("SELECT count(*) AS count FROM stories").get()!.count; }
  revision(): number { return this.db.query<{ value: number }, []>("SELECT value FROM settings WHERE key='revision'").get()!.value; }
  pageStories(limit: number, cursor: { createdAt: string; id: string } | null): StoryRecord[] {
    const rows = cursor
      ? this.db.query<StoryRow, [string, string, string, number]>(`${storySelect} WHERE s.created_at<? OR (s.created_at=? AND s.id>?) ORDER BY s.created_at DESC,s.id LIMIT ?`).all(cursor.createdAt, cursor.createdAt, cursor.id, limit)
      : this.db.query<StoryRow, [number]>(`${storySelect} ORDER BY s.created_at DESC,s.id LIMIT ?`).all(limit);
    return rows.map(row => this.story(row));
  }
  deleteStory(id: string) {
    this.db.transaction(() => {
      // A worker may still hold a snapshot. Removing its lease prevents publishing it.
      this.db.query("UPDATE jobs SET status='completed',lease_owner=NULL,lease_until=NULL,error=NULL WHERE story_id=?").run(id);
      this.db.query("DELETE FROM stories WHERE id=?").run(id);
      this.db.query("DELETE FROM reading_states WHERE story_id=?").run(id);
    }).immediate();
  }
  owns(job: ClaimedJob): boolean {
    return !!this.db.query("SELECT id FROM jobs WHERE id=? AND lease_owner=? AND status='running' AND lease_until>?").get(job.id, job.leaseOwner, Date.now());
  }
  saveStory(story: StoryRecord) {
    const { readingStatus, readingStatusRevision, ...document } = story;
    this.db.query("INSERT INTO stories VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET document=excluded.document, updated_at=excluded.updated_at")
      .run(story.id, JSON.stringify(document), story.createdAt, story.updatedAt);
  }
  setReadingStatus(id: string, status: ReadingStatus): StoryRecord {
    return this.db.transaction(() => {
      const story = this.getStory(id);
      if (!story) throw new APIError(404, "短文不存在");
      if (story.readingStatus === status) return story;
      this.db.query("UPDATE settings SET value=value+1 WHERE key='revision'").run();
      this.db.query("INSERT INTO reading_states VALUES (?,?,?) ON CONFLICT(story_id) DO UPDATE SET status=excluded.status,revision=excluded.revision")
        .run(id, status, this.revision());
      return this.getStory(id)!;
    }).immediate();
  }
  assetStatus(id: string, kind: "cover" | "audio", status: AssetStatus, version?: string) {
    this.db.transaction(() => {
      const story = this.getStory(id);
      if (!story) return;
      story[`${kind}Status`] = status;
      if (version !== undefined) story[`${kind}Version`] = version;
      story.updatedAt = new Date().toISOString();
      this.saveStory(story);
    }).immediate();
  }
  private job(row: JobRow): Job {
    const payload = JSON.parse(row.payload);
    return { id: row.id, kind: row.kind, storyId: row.story_id, status: row.status, request: payload.request ?? this.getStory(row.story_id)?.generationRequest ?? null, sentenceIndex: payload.index ?? null, createdAt: row.created_at, updatedAt: row.updated_at, error: row.error, attempts: row.attempts };
  }
  getJob(id: string): Job | null {
    const row = this.db.query<JobRow, [string]>("SELECT * FROM jobs WHERE id=?").get(id);
    return row ? this.job(row) : null;
  }
  listJobs(): Job[] {
    return this.db.query<JobRow, []>("SELECT * FROM jobs WHERE status != 'completed' ORDER BY created_at DESC LIMIT 200").all().map(r => this.job(r));
  }
  enqueue(kind: JobKind, storyId: string, payload: { request?: GenerationRequest; index?: number } = {}, key?: string, limits?: { dailyJobLimit: number; maxQueuedJobs: number }): Job {
    return this.db.transaction(() => {
      const fingerprint = JSON.stringify({ kind, storyId: kind === "story" ? null : storyId, payload });
      if (key) {
        const existing = this.db.query<JobRow, [string]>("SELECT * FROM jobs WHERE idempotency_key=?").get(key);
        if (existing) {
          if (existing.fingerprint !== fingerprint) throw new APIError(409, "同一幂等标识不能用于不同请求");
          return this.job(existing);
        }
      }
      const activeKey = `${kind}:${storyId}:${payload.index ?? ""}`;
      const active = this.db.query<JobRow, [string]>("SELECT * FROM jobs WHERE active_key=? AND status IN ('queued','running')").get(activeKey);
      if (active) return this.job(active);
      if (limits) this.checkLimits(limits);
      const now = new Date().toISOString(), id = crypto.randomUUID();
      this.db.query("INSERT INTO jobs (id,kind,story_id,status,payload,created_at,updated_at,idempotency_key,fingerprint,active_key) VALUES (?,?,?,'queued',?,?,?,?,?,?)")
        .run(id, kind, storyId, JSON.stringify(payload), now, now, key ?? null, fingerprint, activeKey);
      if (kind === "cover" || kind === "audio") this.assetStatus(storyId, kind, "queued");
      return this.getJob(id)!;
    }).immediate();
  }
  private checkLimits(limits: { dailyJobLimit: number; maxQueuedJobs: number }) {
    const pending = this.db.query<{ n: number }, []>("SELECT count(*) AS n FROM jobs WHERE status IN ('queued','running')").get()!.n;
    const today = new Date().toISOString().slice(0, 10);
    const daily = this.db.query<{ n: number }, [string]>("SELECT coalesce(sum(max(attempts,1)),0) AS n FROM jobs WHERE created_at>=?").get(today)!.n;
    if (pending >= limits.maxQueuedJobs || daily >= limits.dailyJobLimit) throw new APIError(429, "已达到任务数量限制，请稍后再试");
  }
  retry(id: string, limits: { dailyJobLimit: number; maxQueuedJobs: number }): Job {
    return this.db.transaction(() => {
      const job = this.getJob(id);
      if (!job) throw new APIError(404, "任务不存在");
      if (job.status !== "failed") return job;
      if (job.attempts >= 3) throw new APIError(409, "该任务已重试三次，请检查服务日志");
      this.checkLimits(limits);
      const key = `${job.kind}:${job.storyId}:${job.sentenceIndex ?? ""}`;
      if (this.db.query("SELECT id FROM jobs WHERE active_key=? AND status IN ('queued','running')").get(key)) throw new APIError(409, "已有相同任务正在执行");
      this.db.query("UPDATE jobs SET status='queued',error=NULL,updated_at=? WHERE id=?").run(new Date().toISOString(), id);
      if (job.kind === "cover" || job.kind === "audio") this.assetStatus(job.storyId, job.kind, "queued");
      return this.getJob(id)!;
    }).immediate();
  }
  dismiss(id: string) {
    // Retain idempotency history, but hide dismissed failures from the active list.
    const job = this.getJob(id);
    if (job?.status === "queued" || job?.status === "running") throw new APIError(409, "任务仍在执行");
    this.db.query("UPDATE jobs SET status='completed' WHERE id=?").run(id);
  }
  claim(owner: string): ClaimedJob | null {
    return this.db.transaction(() => {
      // An interrupted paid request has an uncertain outcome. Surface it for explicit retry.
      const interrupted = this.db.query<JobRow, [number]>("SELECT * FROM jobs WHERE status='running' AND lease_until<?").all(Date.now());
      this.db.query("UPDATE jobs SET status='failed',error='Worker 中断，请重试任务',lease_owner=NULL,lease_until=NULL,updated_at=? WHERE status='running' AND lease_until<?")
        .run(new Date().toISOString(), Date.now());
      for (const job of interrupted) if (job.kind === "cover" || job.kind === "audio") this.assetStatus(job.story_id, job.kind, "failed");
      const row = this.db.query<JobRow, []>("SELECT * FROM jobs WHERE status='queued' ORDER BY CASE kind WHEN 'story' THEN 0 WHEN 'analysis' THEN 1 WHEN 'cover' THEN 2 ELSE 3 END,created_at,rowid LIMIT 1").get();
      if (!row) return null;
      this.db.query("UPDATE jobs SET status='running',attempts=attempts+1,lease_owner=?,lease_until=?,updated_at=? WHERE id=?")
        .run(owner, Date.now() + 60000, new Date().toISOString(), row.id);
      if (row.kind === "cover" || row.kind === "audio") this.assetStatus(row.story_id, row.kind, "running");
      return { ...this.getJob(row.id)!, leaseOwner: owner };
    }).immediate();
  }
  heartbeat(job: ClaimedJob): boolean {
    return this.db.query("UPDATE jobs SET lease_until=? WHERE id=? AND lease_owner=? AND status='running'").run(Date.now() + 60000, job.id, job.leaseOwner).changes === 1;
  }
  finish(job: ClaimedJob, error: string | null = null) {
    this.db.transaction(() => {
      const result = this.db.query("UPDATE jobs SET status=?,error=?,lease_owner=NULL,lease_until=NULL,updated_at=? WHERE id=? AND lease_owner=?")
        .run(error ? "failed" : "completed", error, new Date().toISOString(), job.id, job.leaseOwner);
      if (result.changes && error && (job.kind === "cover" || job.kind === "audio")) this.assetStatus(job.storyId, job.kind, "failed");
    }).immediate();
  }
  addSession(hash: string) {
    this.db.query("DELETE FROM sessions WHERE expires_at<?").run(Date.now());
    this.db.query("INSERT INTO sessions VALUES (?,?)").run(hash, Date.now() + 7 * 86400000);
  }
  hasSession(hash: string): boolean { return !!this.db.query("SELECT hash FROM sessions WHERE hash=? AND expires_at>?").get(hash, Date.now()); }
  deleteSession(hash: string) { this.db.query("DELETE FROM sessions WHERE hash=?").run(hash); }
}
