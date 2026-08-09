import { Buffer } from "node:buffer";

export const PCM_SAMPLE_RATE = 16_000;
export const PCM_CHANNEL_COUNT = 1;
export const PCM_BYTES_PER_SAMPLE = 2;
export const MIN_AUDIO_DURATION_MS = 200;
export const MAX_AUDIO_DURATION_MS = 30_000;
export const MAX_PCM_BYTES =
	(PCM_SAMPLE_RATE * PCM_CHANNEL_COUNT * PCM_BYTES_PER_SAMPLE *
		MAX_AUDIO_DURATION_MS) /
	1000;

export function pcmDurationMs(byteLength: number): number {
	const bytesPerSecond =
		PCM_SAMPLE_RATE * PCM_CHANNEL_COUNT * PCM_BYTES_PER_SAMPLE;
	return Math.round((byteLength * 1000) / bytesPerSecond);
}

export function buildPcm16Wav(pcm: Uint8Array): Uint8Array {
	const headerLength = 44;
	const wav = new Uint8Array(headerLength + pcm.byteLength);
	const view = new DataView(wav.buffer);
	const byteRate = PCM_SAMPLE_RATE * PCM_CHANNEL_COUNT * PCM_BYTES_PER_SAMPLE;

	writeAscii(wav, 0, "RIFF");
	view.setUint32(4, 36 + pcm.byteLength, true);
	writeAscii(wav, 8, "WAVE");
	writeAscii(wav, 12, "fmt ");
	view.setUint32(16, 16, true);
	view.setUint16(20, 1, true);
	view.setUint16(22, PCM_CHANNEL_COUNT, true);
	view.setUint32(24, PCM_SAMPLE_RATE, true);
	view.setUint32(28, byteRate, true);
	view.setUint16(32, PCM_CHANNEL_COUNT * PCM_BYTES_PER_SAMPLE, true);
	view.setUint16(34, PCM_BYTES_PER_SAMPLE * 8, true);
	writeAscii(wav, 36, "data");
	view.setUint32(40, pcm.byteLength, true);
	wav.set(pcm, headerLength);
	return wav;
}

export function wavToBase64(wav: Uint8Array): string {
	return Buffer.from(wav.buffer, wav.byteOffset, wav.byteLength).toString(
		"base64",
	);
}

function writeAscii(target: Uint8Array, offset: number, value: string): void {
	for (let index = 0; index < value.length; index += 1) {
		target[offset + index] = value.charCodeAt(index);
	}
}
