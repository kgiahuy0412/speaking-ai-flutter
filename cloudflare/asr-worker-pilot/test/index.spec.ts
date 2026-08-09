import {
	env,
	createExecutionContext,
	waitOnExecutionContext,
	SELF,
} from "cloudflare:test";
import { beforeEach, describe, expect, it, vi } from "vitest";
import worker, { handleRequest, type PilotEnv } from "../src/index";

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;
const TEST_TOKEN = "test-pilot-token";
const SESSION_ID = "audio_v2-test-session";
const SCOPED_TOKEN_SECRET =
	"test-audio-upload-token-secret-with-more-than-thirty-two-characters";

function pcmRequest(options: {
	token?: string;
	body?: Uint8Array;
	overrideHeaders?: Record<string, string>;
} = {}): Request {
	const headers = new Headers({
		Authorization: `Bearer ${options.token ?? TEST_TOKEN}`,
		"Content-Type": "application/octet-stream",
		"X-Audio-Session-Id": SESSION_ID,
		"X-Snapshot-Chunk-Count": "3",
		"X-Audio-Sample-Rate": "16000",
		"X-Audio-Channels": "1",
		"X-Audio-Encoding": "pcm_s16le",
		...options.overrideHeaders,
	});
	return new IncomingRequest("https://example.com/v1/asr/transcribe", {
		method: "POST",
		headers,
		body: options.body ?? new Uint8Array(6400),
	});
}

function fakeEnv(
	run = vi.fn().mockResolvedValue({ text: "Con muốn uống nước", word_count: 4 }),
) {
	return {
		AI: { run },
		PILOT_API_TOKEN: TEST_TOKEN,
	} as unknown as PilotEnv;
}

async function issueScopedToken({
	sessionId = SESSION_ID,
	expiresAt = Math.floor(Date.now() / 1000) + 900,
}: {
	sessionId?: string;
	expiresAt?: number;
} = {}): Promise<string> {
	const claims = {
		protocolVersion: 2,
		encoding: "pcm_s16le",
		requestedSampleRate: 16000,
		channelCount: 1,
		bitsPerSample: 16,
		sourceChunkDurationMs: 200,
		maxDurationMs: 12000,
		sessionId,
		expiresAt,
		maxChunkBytes: 1024 * 1024,
		maxSessionBytes: 16 * 1024 * 1024,
		maxChunks: 1000,
	};
	const payload = bytesToBase64Url(
		new TextEncoder().encode(JSON.stringify(claims)),
	);
	const key = await crypto.subtle.importKey(
		"raw",
		new TextEncoder().encode(SCOPED_TOKEN_SECRET),
		{ name: "HMAC", hash: "SHA-256" },
		false,
		["sign"],
	);
	const signature = new Uint8Array(
		await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)),
	);
	return `${payload}.${bytesToBase64Url(signature)}`;
}

function bytesToBase64Url(value: Uint8Array): string {
	let binary = "";
	for (const byte of value) {
		binary += String.fromCharCode(byte);
	}
	return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

describe("ASR Worker pilot", () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});
	it("reports health without invoking Workers AI (unit style)", async () => {
		const request = new IncomingRequest("http://example.com/health");
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		const body = await response.json<{
			status: string;
			service: string;
			aiBindingAvailable: boolean;
			timestamp: string;
		}>();
		expect(body.status).toBe("ok");
		expect(body.service).toBe("asr-worker-pilot");
		expect(typeof body.aiBindingAvailable).toBe("boolean");
		expect(Number.isNaN(Date.parse(body.timestamp))).toBe(false);
	});

	it("reports health through the Worker runtime (integration style)", async () => {
		const response = await SELF.fetch("https://example.com/health");

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			status: "ok",
			service: "asr-worker-pilot",
		});
	});

	it("wraps PCM as WAV and calls the real Workers AI model contract", async () => {
		const run = vi
			.fn()
			.mockResolvedValue({ text: "Con muốn uống nước", word_count: 4 });
		const response = await handleRequest(pcmRequest(), fakeEnv(run));

		expect(response.status).toBe(200);
		const body = await response.json<{
			transcript: string;
			provider: string;
			model: string;
			audioDurationMs: number;
		}>();
		expect(body).toMatchObject({
			transcript: "Con muốn uống nước",
			provider: "cloudflare_workers_ai",
			model: "@cf/openai/whisper-large-v3-turbo",
			audioDurationMs: 200,
		});
		expect(run).toHaveBeenCalledOnce();
		const [model, input] = run.mock.calls[0];
		expect(model).toBe("@cf/openai/whisper-large-v3-turbo");
		expect(input).toMatchObject({
			task: "transcribe",
			language: "vi",
			vad_filter: false,
			beam_size: 2,
			condition_on_previous_text: false,
		});
		expect(input.audio).toMatch(/^UklGR/);
		expect(response.headers.get("Server-Timing")).toContain("asr;dur=");
	});

	it("does not call Workers AI without the pilot token", async () => {
		const run = vi.fn();
		const request = pcmRequest({ token: "wrong-token" });
		const response = await handleRequest(request, fakeEnv(run));

		expect(response.status).toBe(401);
		expect(await response.json()).toEqual({ error: "unauthorized" });
		expect(run).not.toHaveBeenCalled();
	});

	it("accepts the backend scoped audio-session token without exposing the pilot secret", async () => {
		const run = vi
			.fn()
			.mockResolvedValue({ text: "Con muốn uống nước", word_count: 4 });
		const token = await issueScopedToken();
		const response = await handleRequest(
			pcmRequest({ token }),
			{
				AI: { run },
				AUDIO_UPLOAD_TOKEN_SECRET: SCOPED_TOKEN_SECRET,
			} as unknown as PilotEnv,
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			transcript: "Con muốn uống nước",
			authMode: "scoped_audio_session",
		});
		expect(run).toHaveBeenCalledOnce();
	});

	it("rejects an expired scoped audio-session token before calling Workers AI", async () => {
		const run = vi.fn();
		const token = await issueScopedToken({
			expiresAt: Math.floor(Date.now() / 1000) - 1,
		});
		const response = await handleRequest(
			pcmRequest({ token }),
			{
				AI: { run },
				AUDIO_UPLOAD_TOKEN_SECRET: SCOPED_TOKEN_SECRET,
			} as unknown as PilotEnv,
		);

		expect(response.status).toBe(410);
		expect(await response.json()).toEqual({
			error: "audio_session_token_expired",
		});
		expect(run).not.toHaveBeenCalled();
	});

	it("rejects PCM with incorrect sample-rate metadata", async () => {
		const run = vi.fn();
		const request = pcmRequest({
			overrideHeaders: { "X-Audio-Sample-Rate": "48000" },
		});
		const response = await handleRequest(request, fakeEnv(run));

		expect(response.status).toBe(400);
		expect(await response.json()).toEqual({
			error: "sample_rate_must_be_16000",
		});
		expect(run).not.toHaveBeenCalled();
	});

	it("rejects audio shorter than 200 ms", async () => {
		const run = vi.fn();
		const response = await handleRequest(
			pcmRequest({ body: new Uint8Array(3200) }),
			fakeEnv(run),
		);

		expect(response.status).toBe(422);
		expect(await response.json()).toEqual({ error: "audio_too_short" });
		expect(run).not.toHaveBeenCalled();
	});

	it("returns a distinct response for Workers AI rate limits", async () => {
		const run = vi.fn().mockRejectedValue(new Error("429 rate limit exceeded"));
		const response = await handleRequest(pcmRequest(), fakeEnv(run));

		expect(response.status).toBe(429);
		expect(await response.json()).toMatchObject({
			error: "workers_ai_rate_limited",
		});
	});

	it("identifies an exhausted daily neuron allocation", async () => {
		const run = vi.fn().mockRejectedValue(
			new Error(
				"4006: you have used up your daily free allocation of 10,000 neurons",
			),
		);
		const response = await handleRequest(pcmRequest(), fakeEnv(run));

		expect(response.status).toBe(429);
		expect(await response.json()).toMatchObject({
			error: "workers_ai_quota_exhausted",
		});
		expect(response.headers.get("Server-Timing")).toContain("asr;dur=");
	});

	it("returns JSON 404 for unknown routes", async () => {
		const response = await SELF.fetch("https://example.com/unknown");

		expect(response.status).toBe(404);
		expect(await response.json()).toEqual({ error: "not_found" });
	});
});
