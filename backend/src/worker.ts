import type { Config } from "./config";
import { rm } from "node:fs/promises";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { Gateway, type AIProvider } from "./gateway";
import { AssetGenerator } from "./assets";
import { Store, type ClaimedJob } from "./store";
import { APIError, parseAnalysis, parseContent, type StoryRecord } from "./types";
import { analysisPrompt, analysisSchema, storySchema, storySystem, storyUser } from "./prompts";

export class Worker {
  private readonly owner = crypto.randomUUID();
  private readonly assets: AssetGenerator;
  constructor(private store: Store, private config: Config, private ai: AIProvider = new Gateway(config)) { this.assets = new AssetGenerator(config, ai); }
  async runLoop(signal: AbortSignal): Promise<void> {
    console.info(JSON.stringify({ event: "worker.started" }));
    while (!signal.aborted) {
      try {
        if (await this.tick(signal)) continue;
      } catch (error) {
        console.error(JSON.stringify({ event: "worker.error", errorType: error instanceof Error ? error.name : "unknown" }));
      }
      try { await delay(1000, undefined, { signal }); }
      catch (error) { if (!signal.aborted) throw error; }
    }
  }
  async tick(signal?: AbortSignal): Promise<boolean> {
    if (signal?.aborted) return false;
    const job = this.store.claim(this.owner);
    if (!job) return false;
    const controller = new AbortController();
    const abort = () => controller.abort(new Error("Worker 正在停止，请重试任务"));
    signal?.addEventListener("abort", abort, { once: true });
    const timer = setInterval(() => { if (!this.store.heartbeat(job)) controller.abort(new Error("任务租约已失效")); }, 10000);
    try {
      await this.run(job, controller.signal);
      this.store.finish(job);
      console.info(JSON.stringify({ event: "job.completed", jobId: job.id, kind: job.kind }));
    } catch (error) {
      const message = controller.signal.aborted ? "Worker 中断，请重试任务" : error instanceof APIError ? error.message : "任务执行失败，请检查服务日志后重试";
      this.store.finish(job, message);
      // Do not log provider payloads, prompts or credentials.
      console.error(JSON.stringify({ event: "job.failed", jobId: job.id, kind: job.kind, message, errorType: error instanceof Error ? error.name : "unknown" }));
    } finally { clearInterval(timer); signal?.removeEventListener("abort", abort); }
    return true;
  }
  private async run(job: ClaimedJob, signal: AbortSignal) {
    if (job.kind === "story") {
      // A committed story is a checkpoint: retry only unfinished work after interruption.
      let story = this.store.getStory(job.storyId);
      if (!story) {
        const request = job.request!;
        const content = parseContent(await this.ai.structured(storySystem, storyUser(request, this.store.listStories(50)), "story", storySchema, signal));
        signal.throwIfAborted();
        const now = new Date().toISOString();
        story = { id: job.storyId, createdAt: now, updatedAt: now, language: request.language, level: request.level, genre: request.genre, generationRequest: request, content, analyses: {}, coverStatus: "missing", audioStatus: "missing", coverVersion: null, audioVersion: null };
        this.store.db.transaction(() => { if (this.store.owns(job)) this.store.saveStory(story!); }).immediate();
      }
      this.store.db.transaction(() => {
        if (!this.store.owns(job) || !this.store.getStory(job.storyId)) return;
        if (story!.coverStatus === "missing") this.store.enqueue("cover", story!.id);
        if (story!.audioStatus === "missing") this.store.enqueue("audio", story!.id);
      }).immediate();
      return;
    }
    const story = this.store.getStory(job.storyId);
    if (!story) throw new APIError(404, "短文不存在");
    if (job.kind === "analysis") {
      const index = job.sentenceIndex!;
      if (story.analyses[String(index)]) return;
      const prompt = analysisPrompt(story, index);
      const analysis = parseAnalysis(await this.ai.structured(prompt.system, prompt.user, "analysis", analysisSchema, signal));
      signal.throwIfAborted();
      this.store.db.transaction(() => {
        if (!this.store.owns(job)) return;
        const current = this.store.getStory(story.id);
        if (!current) return;
        current.analyses[String(index)] = analysis;
        current.updatedAt = new Date().toISOString();
        this.store.saveStory(current);
      }).immediate();
    } else {
      const version = await this.assets[job.kind](story, signal);
      signal.throwIfAborted();
      const published = this.store.db.transaction(() => {
        if (!this.store.owns(job) || !this.store.getStory(story.id)) return false;
        this.store.assetStatus(story.id, job.kind as "cover" | "audio", "ready", version);
        return true;
      }).immediate();
      if (!published) await rm(join(this.config.dataDir, "assets", story.id, version), { recursive: true, force: true });
    }
  }
}
