import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const readJson = async file => JSON.parse(await readFile(path.join(root, file), 'utf8'));
const manifest = await readJson('assets/data/cloudinary_audio_manifest.json');
const byAsset = new Map(manifest.clips.map(clip => [clip.asset, clip]));
const urls = new Set(manifest.clips.map(clip => clip.url));
assert.equal(byAsset.size, manifest.totalFiles);
assert.equal(urls.size, manifest.totalFiles);
let totalBytes = 0;
for (const clip of manifest.clips) {
  const url = new URL(clip.url);
  assert.equal(url.protocol, 'https:');
  assert.equal(url.hostname, 'res.cloudinary.com');
  assert.equal(decodeURIComponent(url.pathname), `/${manifest.cloudName}/video/upload/v${clip.version}/${clip.publicId}.mp3`);
  const bytes = await readFile(path.join(root, clip.asset));
  assert.equal(bytes.length, clip.bytes, clip.asset);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), clip.sha256, clip.asset);
  totalBytes += bytes.length;
}
assert.equal(totalBytes, manifest.totalBytes);
const files = await readdir(path.join(root, 'assets/audio'), { recursive: true, withFileTypes: true });
assert.equal(files.filter(file => file.isFile() && /\.mp3$/i.test(file.name)).length, manifest.totalFiles);
let references = 0;
function inspect(value) {
  if (typeof value === 'string') {
    assert.ok(!value.startsWith('asset:'), `Remaining asset URI: ${value}`);
    if (value.startsWith('https://res.cloudinary.com/')) {
      assert.ok(urls.has(value), `Unknown Cloudinary URL: ${value}`);
      references++;
    }
  } else if (Array.isArray(value)) {
    value.forEach(inspect);
  } else if (value && typeof value === 'object') {
    if (value.asset?.startsWith('assets/audio/')) {
      assert.equal(value.audioUrl, byAsset.get(value.asset)?.url, `Mismatched clip: ${value.asset}`);
    }
    Object.values(value).forEach(inspect);
  }
}
for (const file of ['homi_audio_index.json', 'elevenlabs_prompt_index.json', 'listening_lessons.json', 'listening_audio_manifest_v4.json']) {
  inspect(await readJson(`assets/data/${file}`));
}
const pubspec = await readFile(path.join(root, 'pubspec.yaml'), 'utf8');
assert.ok(!/^\s*-\s+assets\/audio\//m.test(pubspec), 'MP3 directories remain in bundle configuration');
assert.ok(pubspec.includes('    - assets/data/cloudinary_audio_manifest.json'));
const report = { cloudName: manifest.cloudName, audioFiles: manifest.totalFiles, totalBytes, linkedReferences: references, sourceHashesVerified: true, bundledAudioDirectories: 0 };
await mkdir(path.join(root, 'build/cloudinary'), { recursive: true });
await writeFile(path.join(root, 'build/cloudinary/link-verification.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
