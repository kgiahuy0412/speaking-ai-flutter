import { createHash } from 'node:crypto';
import { appendFile, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifestPath = path.join(root, 'assets/data/cloudinary_audio_manifest.json');
const checkpointPath = path.join(root, 'build/cloudinary/app-audio-uploads.jsonl');
const options = Object.fromEntries(process.argv.slice(2).map((arg, i, args) =>
  arg.startsWith('--') ? [arg.slice(2), args[i + 1]?.startsWith('--') || !args[i + 1] ? true : args[i + 1]] : []).filter(pair => pair.length));
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function listFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(entry => {
    const target = path.join(directory, entry.name);
    return entry.isDirectory() ? listFiles(target) : target;
  }));
  return nested.flat().sort();
}

async function inventory() {
  const files = (await listFiles(path.join(root, 'assets'))).filter(file => /\.(mp3|wav|m4a|aac|ogg|flac)$/i.test(file));
  const items = [];
  for (const file of files) {
    const bytes = await readFile(file);
    const asset = path.relative(root, file).replaceAll('\\', '/');
    const sha256 = hash(bytes);
    const relative = asset.replace(/^assets\/audio\//, '').replace(/\.[^.]+$/, '');
    const safePath = relative.split('/').map(segment => segment.replace(/[^a-zA-Z0-9_-]/g, '_')).join('/');
    items.push({ asset, bytes: bytes.length, sha256, publicId: `homi/app-audio/v1/${safePath}-${sha256.slice(0, 16)}` });
  }
  if (new Set(items.map(item => item.publicId)).size !== items.length) throw new Error('Duplicate upload identifiers.');
  return items;
}

async function credentials() {
  const values = {};
  if (options.credentials) {
    const contents = await readFile(path.resolve(options.credentials), 'utf8');
    for (const line of contents.split(/\r?\n/)) {
      const match = /^\s*(API Key|API Secret|Cloud Name|CLOUDINARY_API_KEY|CLOUDINARY_API_SECRET|CLOUDINARY_CLOUD_NAME)\s*[:=]\s*(.*?)\s*$/i.exec(line);
      if (match) values[match[1].toLowerCase().replaceAll('_', ' ')] = match[2].replace(/^['"]|['"]$/g, '');
    }
  }
  const config = {
    cloudName: options['cloud-name'] || values['cloud name'] || values['cloudinary cloud name'] || process.env.CLOUDINARY_CLOUD_NAME,
    apiKey: values['api key'] || values['cloudinary api key'] || process.env.CLOUDINARY_API_KEY,
    apiSecret: values['api secret'] || values['cloudinary api secret'] || process.env.CLOUDINARY_API_SECRET,
  };
  if (!/^[a-zA-Z0-9_-]+$/.test(config.cloudName ?? '')) throw new Error('A valid --cloud-name is required.');
  if (options.upload && (!config.apiKey || !config.apiSecret)) throw new Error('API Key and API Secret are required for upload.');
  return config;
}

async function readCheckpoint() {
  let contents;
  try { contents = await readFile(checkpointPath, 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return new Map(); throw error; }
  const records = new Map();
  for (const line of contents.split('\n').filter(Boolean)) {
    const item = JSON.parse(line);
    records.set(`${item.cloudName}:${item.asset}:${item.sha256}`, item);
  }
  return records;
}

async function retry(operation) {
  for (let attempt = 0; ; attempt++) {
    try { return await operation(); }
    catch (error) {
      if (attempt >= 4 || (error.status && error.status < 500 && error.status !== 429)) throw error;
      await sleep(1000 * 2 ** attempt);
    }
  }
}

async function upload(item, config) {
  return retry(async () => {
    const parameters = {
      overwrite: 'false',
      public_id: item.publicId,
      timestamp: String(Math.floor(Date.now() / 1000)),
    };
    const signed = Object.keys(parameters).sort().map(key => `${key}=${parameters[key]}`).join('&');
    const signature = createHash('sha1').update(signed + config.apiSecret).digest('hex');
    const form = new FormData();
    for (const [key, value] of Object.entries(parameters)) form.append(key, value);
    form.append('api_key', config.apiKey);
    form.append('signature', signature);
    form.append('file', new Blob([await readFile(path.join(root, item.asset))], { type: 'audio/mpeg' }), path.basename(item.asset));
    const response = await fetch(`https://api.cloudinary.com/v1_1/${config.cloudName}/video/upload`, {
      method: 'POST', body: form, signal: AbortSignal.timeout(90_000),
    });
    if (!response.ok) {
      // Never log API response bodies: authentication errors can contain keys.
      await response.body?.cancel();
      const error = new Error(`Cloudinary upload returned HTTP ${response.status} for ${item.asset}`);
      error.status = response.status;
      throw error;
    }
    const result = await response.json();
    if (result.public_id !== item.publicId || result.resource_type !== 'video' || result.bytes !== item.bytes || result.format !== 'mp3') {
      throw new Error(`Upload metadata mismatch for ${item.asset}`);
    }
    const url = new URL(result.secure_url);
    if (url.protocol !== 'https:' || url.hostname !== 'res.cloudinary.com' || !url.pathname.startsWith(`/${config.cloudName}/video/upload/`)) {
      throw new Error(`Unexpected delivery URL for ${item.asset}`);
    }
    return { ...item, cloudName: config.cloudName, url: result.secure_url, version: result.version };
  });
}

async function verify(item) {
  return retry(async () => {
    const response = await fetch(item.url, { signal: AbortSignal.timeout(60_000) });
    if (!response.ok) {
      await response.body?.cancel();
      const error = new Error(`Delivery returned HTTP ${response.status} for ${item.asset}`);
      error.status = response.status;
      throw error;
    }
    const sha = createHash('sha256');
    let bytes = 0;
    for await (const chunk of response.body) { sha.update(chunk); bytes += chunk.length; }
    if (bytes !== item.bytes || sha.digest('hex') !== item.sha256) throw new Error(`Downloaded content differs from original: ${item.asset}`);
    return { ...item, verified: true };
  });
}

async function writeJson(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(value, null, 2) + '\n');
}

async function linkCatalog(items, config) {
  const byAsset = new Map(items.map(item => [item.asset, item]));
  let previousManifest;
  try { previousManifest = JSON.parse(await readFile(manifestPath, 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const previousUrls = new Map((previousManifest?.clips ?? []).map(item => [item.url, item.asset]));
  const updated = [];
  let linkedFields = 0;
  function visit(value) {
    if (typeof value === 'string' && previousUrls.has(value)) {
      const asset = previousUrls.get(value);
      const item = byAsset.get(asset);
      if (!item) throw new Error(`Removed audio is still referenced: ${asset}`);
      linkedFields++;
      return item.url;
    }
    if (typeof value === 'string' && value.startsWith('asset:')) {
      const asset = decodeURIComponent(new URL(value).pathname).replace(/^\/+/, '');
      const item = byAsset.get(asset);
      if (!item) throw new Error(`Unmapped asset reference: ${asset}`);
      linkedFields++;
      return item.url;
    }
    if (Array.isArray(value)) return value.map(visit);
    if (value && typeof value === 'object') {
      const result = Object.fromEntries(Object.entries(value).map(([key, child]) => [key, visit(child)]));
      if (typeof result.asset === 'string' && result.asset.startsWith('assets/audio/')) {
        const item = byAsset.get(result.asset);
        if (!item) throw new Error(`Unmapped audio index entry: ${result.asset}`);
        result.audioUrl = item.url;
        linkedFields++;
      }
      return result;
    }
    return value;
  }
  for (const name of ['homi_audio_index.json', 'elevenlabs_prompt_index.json', 'listening_lessons.json', 'listening_audio_manifest_v4.json']) {
    const file = path.join(root, 'assets/data', name);
    const json = visit(JSON.parse(await readFile(file, 'utf8')));
    if (name === 'listening_lessons.json') json.audioProvider = 'cloudinary-recorded-with-device-cache';
    updated.push([file, json]);
  }
  const homi = updated.find(([file]) => file.endsWith('homi_audio_index.json'))[1];
  const byId = new Map(homi.clips.map(clip => [clip.id, clip.audioUrl]));
  const oldManifest = updated.find(([file]) => file.endsWith('listening_audio_manifest_v4.json'))[1];
  for (const entry of oldManifest.entries) {
    if (byId.has(entry.audioId)) { entry.audioUrl = byId.get(entry.audioId); linkedFields++; }
  }
  // Validate all references before modifying any catalog or the bundle list.
  const pubspecPath = path.join(root, 'pubspec.yaml');
  let pubspec = await readFile(pubspecPath, 'utf8');
  pubspec = pubspec.replace(/^    - assets\/audio\/.*\r?\n/gm, '');
  if (!pubspec.includes('    - assets/data/cloudinary_audio_manifest.json')) {
    pubspec = pubspec.replace('    - assets/data/elevenlabs_prompt_index.json', '    - assets/data/cloudinary_audio_manifest.json\n    - assets/data/elevenlabs_prompt_index.json');
  }
  await writeJson(manifestPath, {
    schemaVersion: 1, cloudName: config.cloudName,
    totalFiles: items.length, totalBytes: items.reduce((total, item) => total + item.bytes, 0),
    clips: items.map(({ asset, url, sha256, bytes, publicId, version }) => ({ asset, url, sha256, bytes, publicId, version })),
  });
  for (const [file, json] of updated) await writeJson(file, json);
  await writeFile(pubspecPath, pubspec);
  console.log(`linked_fields=${linkedFields}; bundled_audio_files=0; manifest=${path.relative(root, manifestPath)}`);
}

async function main() {
  const items = await inventory();
  console.log(`audio_files=${items.length}; bytes=${items.reduce((n, item) => n + item.bytes, 0)}`);
  await writeJson(path.join(root, 'build/cloudinary/app-audio-inventory.json'), { files: items });
  if (!options.upload && !options.verify && !options.link) { console.log('mode=dry-run'); return; }
  const config = await credentials();
  const records = await readCheckpoint();
  await mkdir(path.dirname(checkpointPath), { recursive: true });
  let checkpointWrite = Promise.resolve();
  const persist = record => {
    records.set(`${config.cloudName}:${record.asset}:${record.sha256}`, record);
    checkpointWrite = checkpointWrite.then(() => appendFile(checkpointPath, JSON.stringify(record) + '\n'));
    return checkpointWrite;
  };
  let next = 0;
  let completed = 0;
  let failed = false;
  const results = new Array(items.length);
  const worker = async () => {
    while (!failed) {
      const index = next++;
      if (index >= items.length) return;
      const item = items[index];
      try {
        let record = records.get(`${config.cloudName}:${item.asset}:${item.sha256}`);
        if (!record) {
          if (!options.upload) throw new Error(`Not yet uploaded: ${item.asset}`);
          record = await upload(item, config);
          await persist(record);
        }
        if (!record.verified && (options.verify || options.link)) {
          record = await verify(record);
          await persist(record);
        }
        results[index] = record;
        completed++;
        if (completed % 50 === 0 || completed === items.length) console.log(`completed=${completed}/${items.length}`);
      } catch (error) { failed = true; throw error; }
    }
  };
  const concurrency = Number(options.concurrency ?? 6);
  if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 12) throw new Error('Concurrency must be between 1 and 12.');
  const jobs = await Promise.allSettled(Array.from({ length: concurrency }, worker));
  await checkpointWrite;
  const failure = jobs.find(job => job.status === 'rejected');
  if (failure) throw failure.reason;
  if (options.link) {
    if (results.some(item => !item?.verified)) throw new Error('All files must be verified before linking.');
    await linkCatalog(results, config);
  }
  console.log(`complete=true; uploaded=${results.length}; verified=${results.filter(item => item.verified).length}`);
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
