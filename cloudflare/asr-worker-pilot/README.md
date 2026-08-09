# Cloudflare Worker ASR pilot

Isolated Web-only pilot for comparing direct Raw PCM recognition with the
existing Batch Chunks path. It does not replace the backend pipeline and is
disabled unless the Flutter Web build explicitly enables it. The pilot Worker
is deployed on the separate Cloudflare neuron-test account as
`asr-worker-pilot-neurons`.

## Request flow

1. Flutter Web records mono PCM16 at 16 kHz.
2. The existing Batch chunk uploads continue in parallel as a shadow fallback.
3. At final PCM flush, Flutter sends the retained PCM directly to this Worker.
4. The Worker verifies the backend-issued scoped audio-session token and calls
   `@cf/openai/whisper-large-v3-turbo` through the Workers AI binding.
5. On timeout, quota exhaustion, network failure, or invalid speech, Flutter
   continues the already-running Batch finalize.

No Cloudflare API token or long-lived pilot token is embedded in Flutter.

## Local verification

```powershell
npm install
npx tsc --noEmit
npm test -- --run
npx wrangler deploy --dry-run
```

For local Worker development, copy `.dev.vars.example` to `.dev.vars` and add
local-only values. Never commit `.dev.vars`.

## Cloudflare configuration

The deployed Worker needs:

- AI binding named `AI` (declared in `wrangler.jsonc`).
- Secret `AUDIO_UPLOAD_TOKEN_SECRET` equal to the backend production value so
  it can verify the same short-lived scoped upload token.
- Variable `PILOT_ALLOWED_ORIGIN` equal to the exact Flutter Web origin. The
  pilot is currently restricted to
  `https://innotrik-ai-speaking-worker-pilot.pages.dev`.

Set secrets interactively so their values do not enter shell history:

```powershell
npx wrangler secret put AUDIO_UPLOAD_TOKEN_SECRET
npx wrangler secret put PILOT_API_TOKEN
```

`PILOT_API_TOKEN` is optional and intended only for command-line smoke tests.
Browser traffic should use the scoped token issued by the backend.

## Build the isolated Flutter Web pilot

From the Flutter repository root:

```powershell
flutter build web --release `
  --dart-define=BACKEND_BASE_URL=https://speaking-ai-nextjs-backend-production.up.railway.app `
  --dart-define=ENABLE_WORKER_ASR_PILOT=true `
  --dart-define=WORKER_ASR_PILOT_URL=https://asr-worker-pilot-neurons.asr-worker-pilot.workers.dev
```

Omit `ENABLE_WORKER_ASR_PILOT` (or set it to `false`) to use the unchanged
Batch Chunks Web behavior. Native/APK builds ignore this flag because the
configuration is additionally guarded by `kIsWeb`.

## A/B acceptance criteria

Run 50-100 comparable utterances after Workers AI quota is available. Compare
`browser_streaming` (Worker pilot) with `batch_chunks` using:

- stop-to-result and stop-to-playback P50/P95;
- `workerAsrPilotRttMs` and `workerAsrPilotAsrMs`;
- ASR correctness and fallback rate;
- `workerAsrPilotFallbackCode` for quota, rate-limit, timeout, and network
  failures.

Do not enable the pilot for production users while the Workers AI quota is
exhausted or before the exact Web origin and shared upload-token secret are
configured.
