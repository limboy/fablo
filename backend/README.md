# Fablo backend

Bun + TypeScript, running the HTTP API and background queue runner in one PM2 process named `fablo`. SQLite stores the shared library, cached analyses and durable jobs. Images, AAC narration and word timings live in `DATA_DIR/assets`. The iOS app and future web clients use the same authenticated REST API.

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

Reverse proxy your HTTPS origin to `http://127.0.0.1:3000` (or the configured `HOST`/`PORT`). `PUBLIC_ORIGIN` controls browser-origin checks and secure cookies behind TLS termination. For a separately hosted frontend, add its exact origin to `ALLOWED_ORIGINS`; wildcard origins are unsupported.

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
4. The client refreshes the server library and jobs. Relaunching a client picks up the same records and pending jobs; no local short story database is used.
5. Sentence analysis is generated on demand and cached by the server. Audio and its timeline are downloaded using the same immutable asset version.

The server is authoritative for creation and deletion. There are no import/export endpoints or buttons. The iOS app keeps downloaded data in memory and stores disposable audio files in the system cache, plus connection credentials in Keychain and reading preferences in UserDefaults.

Queued jobs survive restarts. Running jobs use a renewable lease; if the worker is interrupted, an expired job becomes failed and the client can explicitly retry it. This avoids silently repeating a paid upstream request with an uncertain outcome. A committed story is reused when retrying its generation job. Media failures and analysis failures do not remove the text. Queue capacity and daily task limits are configurable; they are task limits rather than billing guarantees.

## REST API

All `/v1` routes require `Authorization: Bearer <FABLO_API_TOKEN>` or a valid session cookie, except session creation. This first version serves one private shared library, with one administrator token.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/health` | API liveness, no auth |
| POST | `/v1/session` | `{ "token": "…" }` → HttpOnly session cookie |
| DELETE | `/v1/session` | Log out the browser session |
| POST | `/v1/generations` | Generation options → job, `202`; requires `Idempotency-Key` |
| GET | `/v1/jobs` | `{ jobs: [...] }`, queued/running/failed jobs |
| GET | `/v1/jobs/{id}` | Job status |
| POST | `/v1/jobs/{id}/retry` | Retry a failed job |
| DELETE | `/v1/jobs/{id}` | Dismiss a terminal job |
| GET | `/v1/stories?limit=50&cursor=...` | `{ stories, nextCursor, revision }`; summaries without paragraphs/analyses |
| GET | `/v1/stories/{id}` | Metadata, `content` and cached `analyses` |
| GET | `/v1/stories/{id}/status` | Summary including asset states and versions |
| DELETE | `/v1/stories/{id}` | Delete from the shared library and invalidate its jobs |
| POST | `/v1/stories/{id}/cover` | Queue cover regeneration |
| POST | `/v1/stories/{id}/audio` | Queue audio regeneration |
| POST | `/v1/stories/{id}/analyses/{index}` | `200 { analysis }` or `202 { job }`; index starts at zero |
| GET/HEAD | `/v1/stories/{id}/assets/{cover\|audio\|timeline}?version={uuid}` | Private resource, with ETag and byte-range support |

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

Web clients can submit the token to `/v1/session` and then use `fetch` with `credentials: "include"`. Cookies use HttpOnly and SameSite=Strict, plus Secure when `PUBLIC_ORIGIN` is HTTPS. A same-origin frontend is the simplest deployment; bearer auth also works for an explicitly allowed frontend origin. Do not compile the administrator token into browser assets.

## Verify

```sh
bun install --frozen-lockfile
bun run typecheck
bun test
bun run test:pm2
```

The PM2 smoke test copies the service source and ecosystem file into a temporary directory with a mock `.env`, its own `PM2_HOME`, database and mock AI Gateway. It checks production `.env` loading, the combined service, real FFmpeg output, HTTP responsiveness during generation, graceful shutdown, queued-job recovery and, on macOS with Swift installed, the production Swift API client. It cleans up its own processes and temporary files. It makes no paid AI requests, never loads the real service's `.env` and never talks to the user's existing PM2 daemon.

Bun/PM2 background service concepts follow the [Bun PM2 guide](https://bun.sh/guides/ecosystem/pm2). The ecosystem file uses PM2's [direct executable launch](https://github.com/Unitech/pm2/blob/master/lib/God/ForkMode.js) to preserve Bun's entry point; database access uses [bun:sqlite](https://bun.sh/docs/runtime/sqlite).
