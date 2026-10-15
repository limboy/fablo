# Fablo backend

Bun + TypeScript, running the HTTP API and background queue runner in one PM2 process named `fablo`. SQLite stores the shared library, cached analyses and durable jobs. Images, AAC narration and word timings live in `DATA_DIR/assets`. The REST API provides public reading access and authenticated library management.

## Deploy on your VPS

Requirements: Bun 1.3 or newer, your existing PM2 installation, FFmpeg (`ffmpeg` and `ffprobe`), and an HTTPS reverse proxy.

```sh
cd backend
bun install --frozen-lockfile
cp .env.example .env
```

Edit `.env`:

- Set `AI_GATEWAY_KEY` to your Vercel AI Gateway key.
- Generate `FABLO_API_TOKEN` with `openssl rand -hex 32`. Enter this token in the iOS connection screen; keep the Gateway key on the server.
- Set `PUBLIC_ORIGIN` to the public HTTPS origin, for example `https://fablo.example.com`.
- Set `DATA_DIR` to a persistent directory owned by the service user. Keep it when updating releases.
- The model IDs match the previous iOS implementation and can be changed with `TEXT_MODEL`, `IMAGE_MODEL`, `SPEECH_MODEL` and `TRANSCRIPTION_MODEL`.

Start the service, setting `BUN_BIN` to Bun's absolute executable path if it is not on PM2's PATH:

```sh
BUN_BIN=/absolute/path/to/bun pm2 start ecosystem.config.cjs
pm2 save
```

The `fablo` service runs as one instance in fork mode. PM2 executes the Bun binary with `interpreter: "none"` and passes `src/server.ts` as its argument. This keeps the server as Bun's entry point; newer PM2 versions otherwise load Bun scripts through a wrapper, which skips the server's `import.meta.main` startup check. Bun loads `.env` from the configured working directory. The HTTP API and queue runner share a database connection; upstream AI requests are asynchronous and FFmpeg runs as a subprocess. On shutdown, the service stops accepting connections, aborts the active generation and settles its job before closing the shared database. To include Fablo in your central ecosystem file:

```js
const { apps: fabloApps } = require("/absolute/path/to/fablo/backend/ecosystem.config.cjs");
module.exports = { apps: [...yourExistingApps, ...fabloApps] };
```

Reverse proxy your HTTPS origin to `http://127.0.0.1:3000` (or the configured `HOST`/`PORT`). `PUBLIC_ORIGIN` controls browser-origin checks and secure cookies behind TLS termination. Public reading works from any browser origin without credentials. For a separately hosted frontend that needs authenticated management, add its exact origin to `ALLOWED_ORIGINS`; wildcard configuration entries are unsupported.

The [Nginx example](nginx.conf.example) starts with an HTTP reverse proxy on port 80 so Certbot can configure HTTPS. Replace `fablo.example.com` and the upstream port as needed. The example belongs inside Nginx's `http` context; on a typical Linux VPS using `conf.d`, install it from the `backend` directory:

```sh
sudo cp nginx.conf.example /etc/nginx/conf.d/fablo.conf
sudoedit /etc/nginx/conf.d/fablo.conf
sudo nginx -t
sudo systemctl reload nginx
```

Once the domain points to your VPS and port 80 is reachable, use [Certbot's Nginx plugin](https://eff-certbot.readthedocs.io/en/stable/using.html#nginx) to obtain and install the certificate and configure HTTPS redirection:

```sh
sudo certbot --nginx -d fablo.example.com
```

After HTTPS is enabled, set `PUBLIC_ORIGIN=https://fablo.example.com` and restart Fablo if you changed `.env`. Keep `HOST=127.0.0.1` so Bun listens locally behind Nginx. Authentication headers, cookies and audio byte ranges pass through to the service, and proxy caching is disabled. Proxy settings follow Nginx's [proxy module documentation](https://nginx.org/en/docs/http/ngx_http_proxy_module.html).

```sh
curl http://127.0.0.1:3000/health
pm2 logs fablo
# After updating code or .env:
pm2 restart ecosystem.config.cjs --update-env
```

If you previously registered `src/server.ts` with `interpreter: "bun"`, recreate the PM2 entry once to apply the direct executable launch:

```sh
pm2 delete fablo
BUN_BIN="$(command -v bun)" pm2 start ecosystem.config.cjs
pm2 save
```

For a proxy error after switching from `bun run dev` to PM2, check `pm2 logs fablo --lines 40 --nostream` for `service.started` and its port. Test `/health` on that local port and make sure Nginx's `proxy_pass` targets the same address. `online` in PM2 alone does not confirm the HTTP server started. If the listener uses an unexpected port, check for inherited `PORT` values and production `.env` overrides.

If you previously started `fablo-api` and `fablo-worker`, remove those two old PM2 entries before starting `fablo` so the old API does not occupy the port:

```sh
pm2 delete fablo-api fablo-worker
pm2 start ecosystem.config.cjs
pm2 save
```

`/health` checks service liveness. Back up the SQLite database using SQLite's online backup facility together with the `assets` directory; copying a live `.sqlite` file alone omits WAL data. Old asset versions are retained so in-flight downloads and database backups can refer to immutable files.

## Local development

Configure `.env` with your keys and set `PUBLIC_ORIGIN=http://localhost:3000`, then start the combined service:

```sh
bun run dev
```

The API and queue runner start together. Run the iOS app in Simulator and connect to `http://localhost:3000` with the configured `FABLO_API_TOKEN`. PM2 can also run the same combined entry point locally.

Press Ctrl+C to stop the service, including in `--watch` mode. It logs `service.stopping`, aborts active generation, drains HTTP requests and closes SQLite before exiting. Shutdown has a 10-second deadline; a second Ctrl+C forces an immediate exit. Forced shutdown exits with code 1; any unsettled running job is recovered as failed after its lease expires on restart.

## Client flow

1. The client sends generation options to `POST /v1/generations` with a fresh `Idempotency-Key`.
2. The server immediately returns `202` and a job. Reusing the same key and payload returns that job; changing the payload with the same key returns `409`.
3. The worker generates and commits the annotated story, then queues independent cover and audio jobs. The story becomes readable before those assets finish.
4. The client restores its cached library and downloaded story details immediately, then refreshes the server library and jobs in the background. A successful complete listing removes local copies of deleted stories and their assets.
5. Sentence analysis is generated on demand and cached by the server and client. Covers, audio and timelines are cached by immutable resource version; an already downloaded audio version plays without a server status request.

The server is authoritative for creation and deletion. Existing content can be uploaded through the authenticated administrative import API described below; the app has no import/export buttons. The iOS app keeps disposable JSON, image and audio caches under `Caches/FabloServer/v1`, separated by a hash of the server URL and access token. Cached text and analyses survive restarts, covers reuse their downloaded version, and audio is published together with its validated matching timeline. Existing downloaded audio is migrated when reused. Connection credentials stay in Keychain and reading preferences in UserDefaults.

Cached content remains available if synchronization fails. Confirmed authorization failures clear that connection's cache; confirmed deletions remove the affected story. Downloads that started before invalidation cannot republish deleted cache records. This supports offline access to previously downloaded content; unopened stories or missing resources still require a connection. Cache files can be reclaimed by the system.

Queued jobs survive restarts. Running jobs use a renewable lease; if the worker is interrupted, an expired job becomes failed and the client can explicitly retry it. This avoids silently repeating a paid upstream request with an uncertain outcome. A committed story is reused when retrying its generation job. Media failures and analysis failures do not remove the text. Queue capacity and daily task limits are configurable; they are task limits rather than billing guarantees.

## REST API

The shared library is publicly readable: story listings, details (including cached analyses), status and assets need no token or session. `GET /v1/stories/{id}/analyses/{index}` reads an existing sentence analysis; it returns `404` if none exists and never queues AI work.

All other `/v1` routes require `Authorization: Bearer <FABLO_API_TOKEN>` or a valid session cookie, except session creation, which validates the token in its body. Generation, imports, deletion, reading-state updates, media regeneration, analysis generation and job listing/status remain administrator operations. `POST` to an analysis endpoint requires authentication even when the analysis is already cached.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/health` | API liveness, no auth |
| POST | `/v1/session` | `{ "token": "…" }` → HttpOnly session cookie |
| DELETE | `/v1/session` | Log out the browser session |
| POST | `/v1/imports` | Upload existing annotated content and optional media; `201` on creation, `200` for an identical repeat |
| POST | `/v1/generations` | Generation options → job, `202`; requires `Idempotency-Key` |
| GET | `/v1/jobs` | `{ jobs: [...] }`, queued/running/failed jobs |
| GET | `/v1/jobs/{id}` | Job status |
| POST | `/v1/jobs/{id}/retry` | Retry a failed job |
| DELETE | `/v1/jobs/{id}` | Dismiss a terminal job |
| GET | `/v1/stories?limit=50&cursor=...` | `{ stories, nextCursor, revision }`; summaries without paragraphs/analyses |
| GET | `/v1/stories/{id}` | Metadata, `content` and cached `analyses` |
| GET | `/v1/stories/{id}/status` | Summary including asset states and versions |
| POST | `/v1/stories/{id}/reading-status` | `{ "status": "unread" \| "reading" \| "read" }` → updated story summary; requires auth |
| DELETE | `/v1/stories/{id}` | Delete from the shared library and invalidate its jobs |
| POST | `/v1/stories/{id}/cover` | Queue cover regeneration |
| POST | `/v1/stories/{id}/audio` | Queue audio regeneration |
| GET | `/v1/stories/{id}/analyses/{index}` | Public cached analysis, `200 { analysis }` or `404`; never generates |
| POST | `/v1/stories/{id}/analyses/{index}` | `200 { analysis }` or `202 { job }`; index starts at zero |
| GET/HEAD | `/v1/stories/{id}/assets/{cover\|audio\|timeline}?version={uuid}` | Public resource, with ETag and byte-range support |

Read without a token (replace the origin and story ID with your deployment's values):

```sh
curl 'https://fablo.example.com/v1/stories?limit=50'
curl "https://fablo.example.com/v1/stories/$STORY_ID"
curl "https://fablo.example.com/v1/stories/$STORY_ID/analyses/0"
curl -o cover.jpg "https://fablo.example.com/v1/stories/$STORY_ID/assets/cover"
```

Browser readers can call these endpoints with ordinary `fetch` requests and no credentials. Public read requests and their `GET`/`HEAD` preflights accept any origin; authenticated browser operations retain the configured origin restrictions. Deploy this backend version and restart the `fablo` PM2 service to enable public reading; no new environment setting is needed. The current iOS connection screen still requires the administrator token for its generation and job-management features.

### Reading boards

Stories start in `unread` (待读); clients can move them to `reading` (在读), `read` (已读), or back to either state. The state belongs to the shared server library, so devices connected to the same server see the same boards after refresh. Story listings, detail and status responses include `readingStatus` and `readingStatusRevision`; the latter increases with successful state changes and protects clients from stale responses. Repeating the current state is a no-op.

Reading state is stored separately in SQLite so cover/audio generation and late story writes cannot overwrite it. Updates advance the library revision for consistent pagination and never enqueue AI jobs. Existing stories default to `unread`; the new table is created automatically on startup. Deploy and restart the backend before using the new iOS menus. The app caches synchronized states for offline viewing and reports failed updates without moving the story to another board.

Generation body:

```json
{
  "language": "en",
  "level": "A2",
  "genre": "日常生活",
  "length": "short",
  "topic": "A rainy morning"
}
```

`language` is `en` or `ja`, `length` is `short`, `medium` or `long`; levels and genres match the iOS selectors. Text is stored in the existing `StoryContent` JSON schema. Dates are ISO 8601 UTC. A story's `coverStatus` and `audioStatus` can be `missing`, `queued`, `running`, `ready` or `failed`; version fields remain available during regeneration. Use the same `audioVersion` for the audio and timeline requests.

Story summaries, detail and status responses include `generationRequest` with the original `language`, `level`, `genre`, `length` and `topic`. The top-level language, level and genre remain available. Existing stories recover the original request from their retained generation jobs on service startup; if no original job exists, `generationRequest` is `null`. Cover, audio and analysis jobs also return this request as `request`, so clients can group jobs by `storyId` and apply the language filter before rendering cards. The iOS library shows one card per story, with resource progress and retry controls inside that card.

Web clients that manage the library can submit the token to `/v1/session` and then use `fetch` with `credentials: "include"`. Cookies use HttpOnly and SameSite=Strict, plus Secure when `PUBLIC_ORIGIN` is HTTPS. A same-origin frontend is the simplest deployment; bearer auth also works for an explicitly allowed frontend origin. Do not compile the administrator token into browser assets.

## Import existing content

Deploy the updated backend and restart `fablo` before uploading. Imports use the existing library token and do not call AI providers or enqueue generation jobs. Readable stories and their existing assets are published together, so clients discover them through the normal library refresh.

On an existing Nginx deployment, update `client_max_body_size` in the active Fablo server block to `20m`, then run `sudo nginx -t` and `sudo systemctl reload nginx`. Keep Certbot's existing TLS configuration. The example now permits 20 MiB uploads; ordinary JSON endpoints retain their 64 KiB limit.

`POST /v1/imports` accepts `multipart/form-data` with these fields:

| Field | Format | Limit |
| --- | --- | --- |
| `story` | JSON string with `source`, `createdAt`, `generationRequest`, `content`, optional `analyses` | 1 MiB |
| `cover` | Optional JPEG file | 4 MiB |
| `audio` | Optional AAC/M4A file | 12 MiB |
| `timeline` | JSON string, required with audio; schema version 3 | 1 MiB |

The whole request must fit within 20 MiB. The server validates media with FFprobe and checks sentence/word counts and timing bounds before publishing. At most two imports are processed simultaneously. A story without audio remains readable and is not automatically charged for regeneration.

`story.source` contains a stable `format` and `id`, plus optional `metadata` (up to 64 KiB) for original fields. The server derives the story UUID from that source. An identical upload returns the existing story without changing its resource versions; a changed upload for the same source returns `409` and leaves the existing story untouched. Interrupted uploads can be retried safely. Original source metadata is returned as `importedFrom` on story detail, not in library summaries.

### Japanese Short Essays adapter

Preparation runs on your computer, separately from the VPS runtime. It reads each folder's `manifest.json`, `essay.md`, cover and optional `audio.mp3` / `audio.srt`. It never modifies the original collection. Install the optional Python preparation dependencies in a virtual environment:

```sh
cd backend
python3 -m venv data/import-venv
data/import-venv/bin/pip install -r scripts/requirements-import.txt
data/import-venv/bin/python scripts/prepare-japanese-import.py \
  "/path/to/Japanese Short Essays" \
  --output data/japanese-import \
  --titles /path/to/chinese-titles.json
```

The optional titles file maps original folder names or Japanese titles to Chinese titles. The adapter preserves Japanese sentences, Chinese translations, original manuscript and metadata; it adds dictionary-based word segmentation, kana readings, romanization and glosses from the original vocabulary tables. Chunk roles are left as `other`; detailed grammar analysis remains available on demand. Mixed N5–N4 entries are catalogued as N4 while retaining the original level in source metadata. Genre and length map to the app's selectors, with original genre and scene retained.

Covers are converted to JPEG and existing MP3 files to AAC/M4A. Sentence boundaries come from the original SRT; word positions inside each sentence are estimated and `isAligned` is `false`. Matching speaker labels are displayed without being timed as spoken words. Missing audio and subtitles are allowed together. The prepared bundle and reports can live in ignored `backend/data`; they are not application source files.

Upload from the local `backend` directory, where Bun reads `FABLO_API_TOKEN` from `.env`:

```sh
bun run import:upload data/japanese-import --server https://fablo.example.com
```

The uploader sends one story at a time, retries transient failures, refuses credential-bearing redirects, and saves progress without storing the token. Rerun the same command after interruption; completed stories are recognized by the server.

### English Short Essays adapter

The English adapter uses the same upload API and media pipeline, with spaCy's local English model for lexical classes and vocabulary lemmas. It retains contractions, hyphenated words and short vocabulary phrases as readable units. English readings and romanization remain empty; translations and vocabulary glosses come from the original files. Install the optional local model in your preparation environment:

```sh
data/import-venv/bin/pip install 'spacy>=3.8,<4'
data/import-venv/bin/python -m spacy download en_core_web_sm
data/import-venv/bin/python scripts/prepare-english-import.py \
  "/path/to/English Short Essays" \
  --output data/english-import \
  --titles /path/to/chinese-titles.json
bun run import:upload data/english-import --server https://fablo.example.com
```

B2–C1 entries are catalogued as C1, with the original range retained in source metadata. Source subtitle segments remain intact, including fragments that belong to longer sentences, to preserve their existing translations and audio boundaries. Missing covers and audio remain absent rather than triggering regeneration. Preparation does not call an AI service or require a backend redeployment.

## Verify

```sh
bun install --frozen-lockfile
bun run typecheck
bun test
python3 tests/prepare-import.test.py
bun run test:pm2
# On macOS with Swift installed:
bun run test:cache
# With a prepared bundle; uses a disposable local server, no real .env or AI:
bun --no-env-file run test:import data/japanese-import
```

The PM2 smoke test copies the service source and ecosystem file into a temporary directory with a mock `.env`, its own `PM2_HOME`, database and mock AI Gateway. It checks production `.env` loading, the combined service, real FFmpeg output, HTTP responsiveness during generation, graceful shutdown, queued-job recovery and, on macOS with Swift installed, the production Swift API client. It cleans up its own processes and temporary files. It makes no paid AI requests, never loads the real service's `.env` and never talks to the user's existing PM2 daemon.

The native cache smoke test launches a fresh Swift client process for each phase, stops its local mock server to verify offline access, and checks that repeated reads do not download the same asset version again. It also verifies version changes, corrupt cache recovery, credential isolation, authorization invalidation and deletion cleanup. All server data and client caches live in a temporary directory.

The import smoke test uploads the prepared collection twice to a temporary local service and checks that no duplicates or generation jobs appear. On macOS it also runs the production Swift client to paginate the whole library, decode all story details, cache every cover, and open each AAC file with its matching word timeline. It does not upload anything to production.

Bun/PM2 background service concepts follow the [Bun PM2 guide](https://bun.sh/guides/ecosystem/pm2). The ecosystem file uses PM2's [direct executable launch](https://github.com/Unitech/pm2/blob/master/lib/God/ForkMode.js) to preserve Bun's entry point; database access uses [bun:sqlite](https://bun.sh/docs/runtime/sqlite).
