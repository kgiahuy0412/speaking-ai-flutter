// Offline asset authoring only. No API credentials are shipped to Flutter.
// node tool/generate_elevenlabs_prompts.mjs --key-file <path> [--limit N]
// Retry/resume reuses successful, hash-verified files. Never retries uncertain
// billed requests automatically. Run with --retry-failed after reviewing errors.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const root = path.resolve(import.meta.dirname, '..');
const output = path.join(root, 'outputs/elevenlabs-voice-pack');
const planPath = path.join(output, 'generation-plan.json');
const manifestPath = path.join(root, 'assets/data/elevenlabs_prompt_index.json');
const statePath = path.join(output, 'generation-state.json');
const hash = value => createHash('sha256').update(value).digest('hex');
const keyPath = option('--key-file', '');
if (!keyPath) throw new Error('Supply --key-file; never pass the secret itself as an argument.');
const key = fs.readFileSync(keyPath, 'utf8').replace(/^\uFEFF/, '').trim();
if (!/^[A-Za-z0-9_-]{20,}$/.test(key)) throw new Error('Invalid key file format.');
const settings = {voiceId: 'nbv4fVbfyLxvuHzyIeDo', modelId: 'eleven_flash_v2_5', languageCode: 'vi', outputFormat: 'mp3_44100_128', voiceSettings: {stability: 0.65, similarity_boost: 0.8, speed: 1.0}};
const plan = JSON.parse(fs.readFileSync(planPath, 'utf8'));
const state = fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : {settings, clips: {}};
if (JSON.stringify(state.settings) !== JSON.stringify(settings)) throw new Error('Generation settings differ from saved state. Use a new pack version.');
fs.mkdirSync(path.join(root, 'assets/audio/elevenlabs_vi'), {recursive: true});
const save = () => fs.writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
const publish = () => {
  const clips = plan.clips.flatMap(c => {
    const s = state.clips[c.id];
    if (s?.status !== 'complete') return [];
    const asset = `assets/audio/elevenlabs_vi/${c.id}.mp3`;
    if (!fs.existsSync(path.join(root, asset)) || hash(fs.readFileSync(path.join(root, asset))) !== s.sha256) return [];
    return [{id: c.id, text: c.text, locale: 'vi-VN', asset, audioIds: c.audioIds ?? []}];
  });
  fs.writeFileSync(manifestPath, JSON.stringify({schemaVersion: 1, ...settings, clips}, null, 2) + '\n');
};

const limit = Number(option('--limit', '100000'));
let done = 0, skipped = 0, failed = 0;
for (const clip of plan.clips) {
  const asset = path.join(root, `assets/audio/elevenlabs_vi/${clip.id}.mp3`);
  const previous = state.clips[clip.id];
  if (previous?.status === 'complete' && previous.text === clip.text && fs.existsSync(asset) && hash(fs.readFileSync(asset)) === previous.sha256) { skipped++; continue; }
  if (previous && !args.includes('--retry-failed')) {
    console.error(`${clip.id}: saved ${previous.status}; review before --retry-failed`);
    failed++; continue;
  }
  if (done >= limit) break;
  state.clips[clip.id] = {text: clip.text, status: 'requesting', startedAt: new Date().toISOString()};
  save();
  try {
    const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${settings.voiceId}?output_format=${settings.outputFormat}`, {
      method: 'POST', headers: {'xi-api-key': key, 'Content-Type': 'application/json'},
      body: JSON.stringify({text: clip.text, model_id: settings.modelId, language_code: settings.languageCode, voice_settings: settings.voiceSettings}),
      signal: AbortSignal.timeout(90000),
    });
    if (!response.ok) {
      const detail = (await response.text()).replaceAll(key, '[REDACTED]').slice(0,1600);
      throw new Error(`HTTP ${response.status}: ${detail}`);
    }
    const bytes = Buffer.from(await response.arrayBuffer());
    if (!/audio\//i.test(response.headers.get('content-type') ?? '') || bytes.length < 1000) throw new Error('Response is not a valid non-empty audio file.');
    fs.writeFileSync(asset, bytes);
    state.clips[clip.id] = {...state.clips[clip.id], status: 'complete', bytes: bytes.length, sha256: hash(bytes), requestId: response.headers.get('request-id'), characterCost: response.headers.get('character-cost'), completedAt: new Date().toISOString()};
    save(); done++;
    if (done % 10 === 0 || done === limit) { publish(); console.log(`${done} created; ${skipped} reused; ${clip.id}`); }
  } catch (error) {
    state.clips[clip.id] = {...state.clips[clip.id], status: 'failed', error: String(error).replaceAll(key, '[REDACTED]')};
    save(); publish();
    console.error(`${clip.id}: ${state.clips[clip.id].error}`);
    failed++;
    break;
  }
}
publish();
console.log(JSON.stringify({created: done, reused: skipped, failed, planned: plan.clips.length}));
if (failed) process.exitCode = 1;
