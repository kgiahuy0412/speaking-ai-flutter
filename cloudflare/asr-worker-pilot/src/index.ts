import {
	buildPcm16Wav,
	MAX_PCM_BYTES,
	MIN_AUDIO_DURATION_MS,
	PCM_CHANNEL_COUNT,
	PCM_SAMPLE_RATE,
	pcmDurationMs,
	wavToBase64,
} from "./audio";

const ASR_MODEL = "@cf/openai/whisper-large-v3-turbo" as const;
const SESSION_ID_PATTERN = /^[A-Za-z0-9._:-]{8,160}$/;
const MAX_CHUNK_COUNT = 100_000;

export interface PilotEnv extends Env {
	PILOT_API_TOKEN?: string;
	PILOT_ALLOWED_ORIGIN?: string;
	AUDIO_UPLOAD_TOKEN_SECRET?: string;
}

type JsonRecord = Record<string, unknown>;
type RequestMetadata = {
	audioSessionId: string;
	snapshotChunkCount: number;
};
type ScopedAudioSessionClaims = {
	protocolVersion: number;
	encoding: string;
	requestedSampleRate: number;
	channelCount: number;
	bitsPerSample: number;
	maxDurationMs: number;
	sessionId: string;
	expiresAt: number;
	maxChunkBytes: number;
	maxSessionBytes: number;
};
type AuthorizedRequest = {
	ok: true;
	mode: "pilot_master" | "scoped_audio_session";
	claims?: ScopedAudioSessionClaims;
};
type RejectedAuthorization = {
	ok: false;
	status: 401 | 403 | 410 | 503;
	error: string;
};

export default {
	async fetch(request, env): Promise<Response> {
		return handleRequest(request, env);
	},
} satisfies ExportedHandler<PilotEnv>;

export async function handleRequest(
	request: Request,
	env: PilotEnv,
): Promise<Response> {
	const requestStartedAt = performance.now();
	const url = new URL(request.url);
	const origin = request.headers.get("Origin");
	const corsHeaders = resolveCorsHeaders(origin, env.PILOT_ALLOWED_ORIGIN);

	if (origin && !corsHeaders) {
		return json({ error: "origin_not_allowed" }, 403);
	}

	if (request.method === "OPTIONS") {
		return new Response(null, {
			status: 204,
			headers: corsHeaders ?? undefined,
		});
	}

	if (request.method === "GET" && url.pathname === "/health") {
		return json(
			{
				status: "ok",
				service: "asr-worker-pilot",
				aiBindingAvailable: Boolean(env.AI),
				timestamp: new Date().toISOString(),
			},
			200,
			corsHeaders,
		);
	}

	if (url.pathname !== "/v1/asr/transcribe") {
		return json({ error: "not_found" }, 404, corsHeaders);
	}
	if (request.method !== "POST") {
		return json({ error: "method_not_allowed" }, 405, corsHeaders, {
			Allow: "POST, OPTIONS",
		});
	}

	const metadata = validateMetadata(request);
	if ("error" in metadata) {
		return json({ error: metadata.error }, 400, corsHeaders);
	}
	const authorization = await authorizeRequest(request, env, metadata);
	if (!authorization.ok) {
		return json(
			{ error: authorization.error },
			authorization.status,
			corsHeaders,
			authorization.status === 401
				? { "WWW-Authenticate": "Bearer" }
				: undefined,
		);
	}

	const declaredLength = parseInteger(request.headers.get("Content-Length"));
	if (declaredLength !== null && declaredLength > MAX_PCM_BYTES) {
		return json({ error: "audio_too_large" }, 413, corsHeaders);
	}

	const readStartedAt = performance.now();
	const pcm = new Uint8Array(await request.arrayBuffer());
	const requestReadMs = elapsedMs(readStartedAt);
	if (pcm.byteLength > MAX_PCM_BYTES) {
		return json({ error: "audio_too_large" }, 413, corsHeaders);
	}
	const scopedClaims = authorization.claims;
	if (
		scopedClaims &&
		(pcm.byteLength > scopedClaims.maxChunkBytes ||
			pcm.byteLength > scopedClaims.maxSessionBytes)
	) {
		return json({ error: "audio_exceeds_session_token_limits" }, 413, corsHeaders);
	}
	if (pcm.byteLength % 2 !== 0) {
		return json({ error: "pcm_byte_length_must_be_even" }, 400, corsHeaders);
	}
	const audioDurationMs = pcmDurationMs(pcm.byteLength);
	if (audioDurationMs < MIN_AUDIO_DURATION_MS) {
		return json({ error: "audio_too_short" }, 422, corsHeaders);
	}
	if (scopedClaims && audioDurationMs > scopedClaims.maxDurationMs) {
		return json({ error: "audio_exceeds_session_duration" }, 413, corsHeaders);
	}

	const wrapStartedAt = performance.now();
	const wav = buildPcm16Wav(pcm);
	const wavWrapMs = elapsedMs(wrapStartedAt);
	const base64StartedAt = performance.now();
	const audio = wavToBase64(wav);
	const base64Ms = elapsedMs(base64StartedAt);

	const asrStartedAt = performance.now();
	let result: Ai_Cf_Openai_Whisper_Large_V3_Turbo_Output;
	try {
		result = await env.AI.run(ASR_MODEL, {
			audio,
			task: "transcribe",
			language: "vi",
			vad_filter: false,
			beam_size: 2,
			condition_on_previous_text: false,
			no_speech_threshold: 0.55,
			compression_ratio_threshold: 2.2,
			log_prob_threshold: -0.8,
		});
	} catch (error) {
		const asrMs = elapsedMs(asrStartedAt);
		const totalMs = elapsedMs(requestStartedAt);
		const failure = classifyWorkersAiError(error);
		const timing = { requestReadMs, wavWrapMs, base64Ms, asrMs, totalMs };
		console.error(
			JSON.stringify({
				event: "worker_asr_failed",
				audioSessionId: metadata.audioSessionId,
				snapshotChunkCount: metadata.snapshotChunkCount,
				authMode: authorization.mode,
				failure: failure.code,
				asrMs,
				totalMs,
				error: safeErrorMessage(error),
			}),
		);
		return json(
			{
				error: failure.code,
				timing,
			},
			failure.status,
			corsHeaders,
			serverTimingHeaders(timing),
		);
	}

	const asrMs = elapsedMs(asrStartedAt);
	const transcript = result.text.trim();
	const totalMs = elapsedMs(requestStartedAt);
	const timing = { requestReadMs, wavWrapMs, base64Ms, asrMs, totalMs };
	if (!transcript) {
		return json(
			{
				error: "unclear_speech",
				audioSessionId: metadata.audioSessionId,
				snapshotChunkCount: metadata.snapshotChunkCount,
				timing,
			},
			422,
			corsHeaders,
			serverTimingHeaders(timing),
		);
	}

	console.log(
		JSON.stringify({
			event: "worker_asr_completed",
			audioSessionId: metadata.audioSessionId,
			snapshotChunkCount: metadata.snapshotChunkCount,
			audioBytes: pcm.byteLength,
			audioDurationMs,
			...timing,
		}),
	);

	return json(
		{
			transcript,
			provider: "cloudflare_workers_ai",
			model: ASR_MODEL,
			authMode: authorization.mode,
			audioSessionId: metadata.audioSessionId,
			snapshotChunkCount: metadata.snapshotChunkCount,
			audioBytes: pcm.byteLength,
			audioDurationMs,
			wordCount: result.word_count,
			transcriptionInfo: result.transcription_info,
			timing,
		},
		200,
		corsHeaders,
		serverTimingHeaders(timing),
	);
}

function validateMetadata(
	request: Request,
):
	| { audioSessionId: string; snapshotChunkCount: number }
	| { error: string } {
	const contentType = request.headers
		.get("Content-Type")
		?.split(";", 1)[0]
		.trim()
		.toLowerCase();
	if (contentType !== "application/octet-stream") {
		return { error: "content_type_must_be_application_octet_stream" };
	}
	const audioSessionId = request.headers.get("X-Audio-Session-Id")?.trim();
	if (!audioSessionId || !SESSION_ID_PATTERN.test(audioSessionId)) {
		return { error: "invalid_audio_session_id" };
	}
	const snapshotChunkCount = parseInteger(
		request.headers.get("X-Snapshot-Chunk-Count"),
	);
	if (
		snapshotChunkCount === null ||
		snapshotChunkCount < 1 ||
		snapshotChunkCount > MAX_CHUNK_COUNT
	) {
		return { error: "invalid_snapshot_chunk_count" };
	}
	if (parseInteger(request.headers.get("X-Audio-Sample-Rate")) !== PCM_SAMPLE_RATE) {
		return { error: "sample_rate_must_be_16000" };
	}
	if (parseInteger(request.headers.get("X-Audio-Channels")) !== PCM_CHANNEL_COUNT) {
		return { error: "channel_count_must_be_1" };
	}
	if (request.headers.get("X-Audio-Encoding")?.trim().toLowerCase() !== "pcm_s16le") {
		return { error: "encoding_must_be_pcm_s16le" };
	}
	return { audioSessionId, snapshotChunkCount };
}

async function authorizeRequest(
	request: Request,
	env: PilotEnv,
	metadata: RequestMetadata,
): Promise<AuthorizedRequest | RejectedAuthorization> {
	const authorization = request.headers.get("Authorization");
	if (!authorization?.startsWith("Bearer ")) {
		return { ok: false, status: 401, error: "unauthorized" };
	}
	const suppliedToken = authorization.slice("Bearer ".length).trim();
	if (!suppliedToken) {
		return { ok: false, status: 401, error: "unauthorized" };
	}

	if (
		env.PILOT_API_TOKEN &&
		(await constantTimeTokenEqual(suppliedToken, env.PILOT_API_TOKEN))
	) {
		return { ok: true, mode: "pilot_master" };
	}

	if (!env.AUDIO_UPLOAD_TOKEN_SECRET) {
		return env.PILOT_API_TOKEN
			? { ok: false, status: 401, error: "unauthorized" }
			: { ok: false, status: 503, error: "worker_auth_not_configured" };
	}

	return verifyScopedAudioSessionToken(
		suppliedToken,
		env.AUDIO_UPLOAD_TOKEN_SECRET,
		metadata.audioSessionId,
	);
}

async function constantTimeTokenEqual(
	suppliedToken: string,
	expectedToken: string,
): Promise<boolean> {
	const [suppliedHash, expectedHash] = await Promise.all([
		hashToken(suppliedToken),
		hashToken(expectedToken),
	]);
	let difference = 0;
	for (let index = 0; index < expectedHash.length; index += 1) {
		difference |= suppliedHash[index] ^ expectedHash[index];
	}
	return difference === 0;
}

async function verifyScopedAudioSessionToken(
	token: string,
	secret: string,
	expectedSessionId: string,
): Promise<AuthorizedRequest | RejectedAuthorization> {
	const parts = token.split(".");
	if (parts.length !== 2 || !parts[0] || !parts[1]) {
		return { ok: false, status: 401, error: "unauthorized" };
	}
	const [payload, suppliedSignature] = parts;
	const key = await crypto.subtle.importKey(
		"raw",
		new TextEncoder().encode(secret),
		{ name: "HMAC", hash: "SHA-256" },
		false,
		["sign"],
	);
	const signature = new Uint8Array(
		await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)),
	);
	const expectedSignature = bytesToBase64Url(signature);
	if (!(await constantTimeTokenEqual(suppliedSignature, expectedSignature))) {
		return { ok: false, status: 401, error: "unauthorized" };
	}

	let claims: ScopedAudioSessionClaims;
	try {
		claims = JSON.parse(
			new TextDecoder().decode(base64UrlToBytes(payload)),
		) as ScopedAudioSessionClaims;
	} catch {
		return { ok: false, status: 401, error: "unauthorized" };
	}
	if (
		claims.sessionId !== expectedSessionId ||
		claims.protocolVersion !== 2 ||
		claims.encoding !== "pcm_s16le" ||
		claims.requestedSampleRate !== PCM_SAMPLE_RATE ||
		claims.channelCount !== PCM_CHANNEL_COUNT ||
		claims.bitsPerSample !== 16
	) {
		return { ok: false, status: 403, error: "audio_session_token_mismatch" };
	}
	if (!Number.isFinite(claims.expiresAt) || claims.expiresAt <= Date.now() / 1000) {
		return { ok: false, status: 410, error: "audio_session_token_expired" };
	}
	if (
		!Number.isFinite(claims.maxChunkBytes) ||
		!Number.isFinite(claims.maxSessionBytes) ||
		!Number.isFinite(claims.maxDurationMs) ||
		claims.maxChunkBytes <= 0 ||
		claims.maxSessionBytes <= 0 ||
		claims.maxDurationMs < MIN_AUDIO_DURATION_MS
	) {
		return { ok: false, status: 403, error: "audio_session_token_invalid" };
	}
	return { ok: true, mode: "scoped_audio_session", claims };
}

function base64UrlToBytes(value: string): Uint8Array {
	const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
	const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
	const decoded = atob(padded);
	return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function bytesToBase64Url(value: Uint8Array): string {
	let binary = "";
	for (const byte of value) {
		binary += String.fromCharCode(byte);
	}
	return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function hashToken(value: string): Promise<Uint8Array> {
	return new Uint8Array(
		await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
	);
}

function resolveCorsHeaders(
	origin: string | null,
	allowedOrigin?: string,
): HeadersInit | null {
	if (!origin) {
		return {};
	}
	if (!allowedOrigin || origin !== allowedOrigin) {
		return null;
	}
	return {
		"Access-Control-Allow-Origin": origin,
		"Access-Control-Allow-Methods": "POST, OPTIONS",
		"Access-Control-Allow-Headers": [
			"Authorization",
			"Content-Type",
			"X-Audio-Session-Id",
			"X-Snapshot-Chunk-Count",
			"X-Audio-Sample-Rate",
			"X-Audio-Channels",
			"X-Audio-Encoding",
		].join(", "),
		"Access-Control-Expose-Headers": "Server-Timing, X-ASR-Model",
		"Access-Control-Max-Age": "600",
		Vary: "Origin",
	};
}

function json(
	body: JsonRecord,
	status: number,
	corsHeaders?: HeadersInit | null,
	extraHeaders?: HeadersInit,
): Response {
	return Response.json(body, {
		status,
		headers: {
			"Cache-Control": "no-store",
			...corsHeaders,
			...extraHeaders,
		},
	});
}

function serverTimingHeaders(timing: {
	requestReadMs: number;
	wavWrapMs: number;
	base64Ms: number;
	asrMs: number;
	totalMs: number;
}): HeadersInit {
	return {
		"Server-Timing": [
			`read;dur=${timing.requestReadMs}`,
			`wav;dur=${timing.wavWrapMs}`,
			`base64;dur=${timing.base64Ms}`,
			`asr;dur=${timing.asrMs}`,
			`total;dur=${timing.totalMs}`,
		].join(", "),
		"X-ASR-Model": ASR_MODEL,
	};
}

function parseInteger(value: string | null): number | null {
	if (!value || !/^\d+$/.test(value)) {
		return null;
	}
	const parsed = Number(value);
	return Number.isSafeInteger(parsed) ? parsed : null;
}

function elapsedMs(startedAt: number): number {
	return Math.max(0, Math.round(performance.now() - startedAt));
}

function classifyWorkersAiError(error: unknown): {
	code:
		| "workers_ai_quota_exhausted"
		| "workers_ai_rate_limited"
		| "workers_ai_failed";
	status: 429 | 502;
} {
	const message = safeErrorMessage(error);
	if (
		/(?:4006|daily free allocation|used up.*neurons|workers paid plan)/i.test(
			message,
		)
	) {
		return { code: "workers_ai_quota_exhausted", status: 429 };
	}
	if (/(?:429|rate.?limit|too many requests)/i.test(message)) {
		return { code: "workers_ai_rate_limited", status: 429 };
	}
	return { code: "workers_ai_failed", status: 502 };
}

function safeErrorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}
