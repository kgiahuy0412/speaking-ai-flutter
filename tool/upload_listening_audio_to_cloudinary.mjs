import { createHash } from 'node:crypto';
import {
  mkdir,
  readFile,
  readdir,
  stat,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(toolDirectory, '..');
const audioRoot = path.join(projectRoot, 'assets', 'audio');
const catalogPath = path.join(
  projectRoot,
  'assets',
  'data',
  'listening_lessons.json',
);
const checkpointPath = path.join(
  projectRoot,
  'build',
  'cloudinary',
  'listening-audio-upload.json',
);
const publicIdPrefix = 'speaking-ai/listening';
const packagePattern =
  /^AIV0_A(\d+)_AGE(\d+)-(\d+)_THEME(\d{2})_/;

const options = parseArguments(process.argv.slice(2));

try {
  await main();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`ERROR: ${message}`);
  process.exitCode = 1;
}

async function main() {
  const fileEnvironment = options.envFile
    ? parseEnvFile(await readFile(path.resolve(options.envFile), 'utf8'))
    : {};
  const environment = { ...fileEnvironment, ...process.env };
  const cloudinary = {
    cloudName: environment.CLOUDINARY_CLOUD_NAME?.trim(),
    apiKey: environment.CLOUDINARY_API_KEY?.trim(),
    apiSecret: environment.CLOUDINARY_API_SECRET?.trim(),
  };

  if (options.upload) {
    const missing = Object.entries(cloudinary)
      .filter(([, value]) => !value)
      .map(([key]) => key);
    if (missing.length > 0) {
      throw new Error(
        `Missing Cloudinary configuration: ${missing.join(', ')}.`,
      );
    }
  }

  const descriptors = await readAudioDescriptors();
  const checkpoint = await readCheckpoint(cloudinary.cloudName);
  const completed = descriptors.filter((descriptor) =>
    isCurrentUpload(checkpoint.uploads[descriptor.publicId], descriptor),
  );
  const pending = descriptors.filter(
    (descriptor) =>
      !isCurrentUpload(checkpoint.uploads[descriptor.publicId], descriptor),
  );
  const selected = options.limit
    ? pending.slice(0, options.limit)
    : pending;
  const totalBytes = descriptors.reduce(
    (sum, descriptor) => sum + descriptor.bytes,
    0,
  );

  console.log(`packages=${new Set(descriptors.map((item) => item.packageName)).size}`);
  console.log(`manifest_entries=${descriptors.length}`);
  console.log(`audio_bytes=${totalBytes}`);
  console.log(`checkpoint_entries=${completed.length}`);
  console.log(`pending_entries=${pending.length}`);
  console.log(`selected_entries=${selected.length}`);
  console.log(`cloud_config=${hasCloudinaryConfig(cloudinary) ? 'present' : 'absent'}`);
  console.log(`mode=${options.upload ? 'upload' : 'dry-run'}`);

  if (!options.upload) {
    return;
  }

  if (!checkpoint.cloudName) {
    checkpoint.cloudName = cloudinary.cloudName;
  }

  if (selected.length > 0) {
    await uploadAll(selected, checkpoint, cloudinary);
  }

  const allComplete = descriptors.every((descriptor) =>
    isCurrentUpload(checkpoint.uploads[descriptor.publicId], descriptor),
  );

  if (options.verify) {
    const verifyTargets = options.limit ? selected : descriptors;
    await verifyUploads(verifyTargets, checkpoint);
  }

  if (options.writeCatalog) {
    if (!allComplete) {
      throw new Error(
        'Cannot update listening_lessons.json until every manifest entry has uploaded.',
      );
    }
    const linked = await updateCatalog(descriptors, checkpoint);
    console.log(`catalog_linked_urls=${linked}`);
  }

  console.log(`upload_complete=${allComplete}`);
  console.log(`checkpoint=${path.relative(projectRoot, checkpointPath).replaceAll('\\', '/')}`);
}

function parseArguments(argumentsList) {
  const result = {
    concurrency: 4,
    envFile: undefined,
    limit: undefined,
    upload: false,
    verify: false,
    writeCatalog: false,
  };

  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    switch (argument) {
      case '--concurrency':
        result.concurrency = positiveInteger(
          argumentsList[++index],
          '--concurrency',
        );
        break;
      case '--env-file':
        result.envFile = requiredValue(argumentsList[++index], '--env-file');
        break;
      case '--limit':
        result.limit = positiveInteger(argumentsList[++index], '--limit');
        break;
      case '--upload':
        result.upload = true;
        break;
      case '--verify':
        result.verify = true;
        break;
      case '--write-catalog':
        result.writeCatalog = true;
        break;
      case '--help':
        printUsage();
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }

  if (!result.upload && (result.verify || result.writeCatalog)) {
    throw new Error('--verify and --write-catalog require --upload.');
  }
  return result;
}

function printUsage() {
  console.log(
    [
      'Usage:',
      '  node tool/upload_listening_audio_to_cloudinary.mjs [options]',
      '',
      'Options:',
      '  --env-file <path>       Load Cloudinary variables from an env file.',
      '  --upload                Perform uploads (default is dry-run).',
      '  --limit <count>         Upload only the first pending files.',
      '  --concurrency <count>   Parallel uploads (default: 4).',
      '  --verify                Verify uploaded delivery URLs.',
      '  --write-catalog         Replace local asset URLs in the JSON catalog.',
    ].join('\n'),
  );
}

function requiredValue(value, flag) {
  if (!value || value.startsWith('--')) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}

function positiveInteger(value, flag) {
  const parsed = Number.parseInt(requiredValue(value, flag), 10);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new Error(`${flag} must be a positive integer.`);
  }
  return parsed;
}

function parseEnvFile(contents) {
  const values = {};
  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }
    const normalized = line.startsWith('export ') ? line.slice(7) : line;
    const separator = normalized.indexOf('=');
    if (separator < 1) {
      continue;
    }
    const key = normalized.slice(0, separator).trim();
    let value = normalized.slice(separator + 1).trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

function hasCloudinaryConfig(cloudinary) {
  return Boolean(
    cloudinary.cloudName && cloudinary.apiKey && cloudinary.apiSecret,
  );
}

async function readAudioDescriptors() {
  const directoryEntries = await readdir(audioRoot, { withFileTypes: true });
  const packageNames = directoryEntries
    .filter((entry) => entry.isDirectory() && packagePattern.test(entry.name))
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right));
  if (packageNames.length === 0) {
    throw new Error(`No listening audio packages found in ${audioRoot}.`);
  }

  const descriptors = [];
  const publicIds = new Set();
  const assetUris = new Set();

  for (const packageName of packageNames) {
    const packageDirectory = path.join(audioRoot, packageName);
    const packageMatch = packagePattern.exec(packageName);
    const manifestPath = path.join(packageDirectory, 'audio_manifest.json');
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    if (!Array.isArray(manifest)) {
      throw new Error(`${manifestPath} must contain a JSON array.`);
    }

    for (const entry of manifest) {
      validateManifestEntry(entry, packageName);
      const relativePath = entry.relative_path.replaceAll('\\', '/');
      const relativeSegments = relativePath.split('/');
      const filePath = path.resolve(packageDirectory, ...relativeSegments);
      const packagePrefix = `${path.resolve(packageDirectory)}${path.sep}`;
      if (!filePath.startsWith(packagePrefix)) {
        throw new Error(`Unsafe relative_path for ${entry.audio_id}.`);
      }
      const fileStats = await stat(filePath);
      if (!fileStats.isFile()) {
        throw new Error(`Audio file is missing: ${filePath}`);
      }
      const fileContents = await readFile(filePath);
      const actualSha256 = createHash('sha256')
        .update(fileContents)
        .digest('hex')
        .toUpperCase();
      if (actualSha256 !== entry.sha256.toUpperCase()) {
        throw new Error(`SHA-256 mismatch for ${entry.audio_id}.`);
      }

      const filename = path.posix.basename(relativePath);
      const filenameWithoutExtension = filename.replace(/\.mp3$/i, '');
      const publicId = `${publicIdPrefix}/${packageName}/audio/${filenameWithoutExtension}`;
      const assetUri = `asset:///assets/audio/${packageName}/${relativePath}`;
      if (!publicIds.add(publicId)) {
        throw new Error(`Duplicate Cloudinary public ID: ${publicId}`);
      }
      if (!assetUris.add(assetUri)) {
        throw new Error(`Duplicate asset URI: ${assetUri}`);
      }

      descriptors.push({
        ageEnd: Number.parseInt(packageMatch[3], 10),
        ageStart: Number.parseInt(packageMatch[2], 10),
        assetUri,
        audioId: entry.audio_id,
        audioType: entry.audio_type,
        bytes: fileStats.size,
        filePath,
        lessonNumber: parseNumber(entry.lesson_id, /^L(\d+)$/, 'lesson ID'),
        packageName,
        publicId,
        sha256: actualSha256,
        sourceText: entry.source_text,
        topicNumber: Number.parseInt(packageMatch[4], 10),
      });
    }
  }

  return descriptors;
}

function validateManifestEntry(entry, packageName) {
  const requiredStrings = [
    'audio_id',
    'audio_type',
    'lesson_id',
    'qa_status',
    'relative_path',
    'sha256',
  ];
  for (const field of requiredStrings) {
    if (typeof entry?.[field] !== 'string' || !entry[field]) {
      throw new Error(`${packageName} has an invalid ${field}.`);
    }
  }
  if (entry.qa_status !== 'PASS') {
    throw new Error(`${entry.audio_id} did not pass QA.`);
  }
  if (!entry.relative_path.toLowerCase().endsWith('.mp3')) {
    throw new Error(`${entry.audio_id} is not an MP3 file.`);
  }
}

function parseNumber(value, pattern, description) {
  const match = pattern.exec(value);
  if (!match) {
    throw new Error(`Invalid ${description}: ${value}`);
  }
  return Number.parseInt(match[1], 10);
}

async function readCheckpoint(cloudName) {
  let checkpoint;
  try {
    checkpoint = JSON.parse(await readFile(checkpointPath, 'utf8'));
  } catch (error) {
    if (error?.code !== 'ENOENT') {
      throw error;
    }
    checkpoint = {
      version: 1,
      cloudName: cloudName ?? null,
      publicIdPrefix,
      uploads: {},
    };
  }

  if (
    checkpoint.version !== 1 ||
    checkpoint.publicIdPrefix !== publicIdPrefix ||
    typeof checkpoint.uploads !== 'object' ||
    checkpoint.uploads === null
  ) {
    throw new Error(`Invalid checkpoint file: ${checkpointPath}`);
  }
  if (cloudName && checkpoint.cloudName && checkpoint.cloudName !== cloudName) {
    throw new Error('The checkpoint belongs to a different Cloudinary cloud.');
  }
  return checkpoint;
}

function isCurrentUpload(upload, descriptor) {
  return Boolean(
    upload &&
      upload.publicId === descriptor.publicId &&
      upload.sha256 === descriptor.sha256 &&
      typeof upload.secureUrl === 'string' &&
      upload.secureUrl.startsWith('https://'),
  );
}

async function uploadAll(descriptors, checkpoint, cloudinary) {
  await mkdir(path.dirname(checkpointPath), { recursive: true });
  let nextIndex = 0;
  let completedCount = 0;
  let checkpointWrite = Promise.resolve();

  function persistCheckpoint() {
    checkpointWrite = checkpointWrite.then(() => writeCheckpoint(checkpoint));
    return checkpointWrite;
  }

  async function worker() {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= descriptors.length) {
        return;
      }
      const descriptor = descriptors[index];
      const response = await uploadWithRetry(descriptor, cloudinary);
      checkpoint.uploads[descriptor.publicId] = {
        publicId: response.public_id,
        secureUrl: response.secure_url,
        sha256: descriptor.sha256,
        bytes: response.bytes,
        format: response.format,
        resourceType: response.resource_type,
        version: response.version,
        uploadedAt: new Date().toISOString(),
      };
      await persistCheckpoint();
      completedCount += 1;
      if (completedCount % 10 === 0 || completedCount === descriptors.length) {
        console.log(`uploaded=${completedCount}/${descriptors.length}`);
      }
    }
  }

  const workerCount = Math.min(options.concurrency, descriptors.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
}

async function uploadWithRetry(descriptor, cloudinary) {
  let lastError;
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      return await uploadOne(descriptor, cloudinary);
    } catch (error) {
      lastError = error;
      const retryable = !error.status || error.status === 429 || error.status >= 500;
      if (!retryable || attempt === 4) {
        break;
      }
      await delay(750 * 2 ** (attempt - 1));
    }
  }
  throw new Error(
    `Upload failed for ${descriptor.audioId}: ${lastError?.message ?? lastError}`,
  );
}

async function uploadOne(descriptor, cloudinary) {
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signedParameters = {
    overwrite: 'true',
    public_id: descriptor.publicId,
    tags: 'speaking-ai,listening',
    timestamp,
  };
  const signature = signCloudinaryParameters(
    signedParameters,
    cloudinary.apiSecret,
  );
  const form = new FormData();
  const contents = await readFile(descriptor.filePath);
  form.append(
    'file',
    new Blob([contents], { type: 'audio/mpeg' }),
    path.basename(descriptor.filePath),
  );
  form.append('api_key', cloudinary.apiKey);
  for (const [key, value] of Object.entries(signedParameters)) {
    form.append(key, value);
  }
  form.append('signature', signature);

  const endpoint = `https://api.cloudinary.com/v1_1/${encodeURIComponent(
    cloudinary.cloudName,
  )}/video/upload`;
  const response = await fetch(endpoint, {
    method: 'POST',
    body: form,
    signal: AbortSignal.timeout(90_000),
  });
  const payload = await parseJsonResponse(response);
  if (!response.ok) {
    const error = new Error(
      payload?.error?.message ?? `Cloudinary returned HTTP ${response.status}.`,
    );
    error.status = response.status;
    throw error;
  }
  if (
    payload.public_id !== descriptor.publicId ||
    payload.resource_type !== 'video' ||
    typeof payload.secure_url !== 'string' ||
    !payload.secure_url.startsWith('https://')
  ) {
    throw new Error(`Unexpected Cloudinary response for ${descriptor.audioId}.`);
  }
  return payload;
}

function signCloudinaryParameters(parameters, apiSecret) {
  const value = Object.entries(parameters)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, parameterValue]) => `${key}=${parameterValue}`)
    .join('&');
  return createHash('sha1').update(`${value}${apiSecret}`).digest('hex');
}

async function parseJsonResponse(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

async function writeCheckpoint(checkpoint) {
  await writeFile(
    checkpointPath,
    `${JSON.stringify(checkpoint, null, 2)}\n`,
    'utf8',
  );
}

async function verifyUploads(descriptors, checkpoint) {
  let nextIndex = 0;
  let verifiedCount = 0;

  async function worker() {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= descriptors.length) {
        return;
      }
      const descriptor = descriptors[index];
      const upload = checkpoint.uploads[descriptor.publicId];
      if (!isCurrentUpload(upload, descriptor)) {
        throw new Error(`No current upload for ${descriptor.audioId}.`);
      }
      await verifyUrlWithRetry(upload.secureUrl, descriptor.audioId);
      verifiedCount += 1;
      if (verifiedCount % 25 === 0 || verifiedCount === descriptors.length) {
        console.log(`verified=${verifiedCount}/${descriptors.length}`);
      }
    }
  }

  const workerCount = Math.min(8, descriptors.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
}

async function verifyUrlWithRetry(url, audioId) {
  let lastStatus;
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: { Range: 'bytes=0-0' },
        signal: AbortSignal.timeout(30_000),
      });
      lastStatus = response.status;
      await response.body?.cancel();
      if (response.ok) {
        return;
      }
    } catch (error) {
      lastStatus = error instanceof Error ? error.message : String(error);
    }
    if (attempt < 4) {
      await delay(500 * 2 ** (attempt - 1));
    }
  }
  throw new Error(`Delivery URL verification failed for ${audioId}: ${lastStatus}`);
}

async function updateCatalog(descriptors, checkpoint) {
  const original = await readFile(catalogPath, 'utf8');
  const catalog = JSON.parse(original);
  const canonicalOriginal = `${JSON.stringify(catalog, null, 2)}\n`;
  if (normalizeLines(original) !== canonicalOriginal) {
    throw new Error(
      'listening_lessons.json is not canonical two-space JSON; update stopped.',
    );
  }

  let linked = 0;
  for (const descriptor of descriptors) {
    const group = exactlyOne(
      catalog.groups,
      (item) =>
        item.startAge === descriptor.ageStart && item.endAge === descriptor.ageEnd,
      `age group ${descriptor.ageStart}-${descriptor.ageEnd}`,
    );
    const topic = exactlyOne(
      group.topics,
      (item) => item.number === descriptor.topicNumber,
      `topic ${descriptor.topicNumber}`,
    );
    const lesson = exactlyOne(
      topic.lessons,
      (item) => item.number === descriptor.lessonNumber,
      `lesson ${descriptor.lessonNumber}`,
    );
    const secureUrl = checkpoint.uploads[descriptor.publicId].secureUrl;

    switch (descriptor.audioType) {
      case 'lesson_opening':
        linkField(lesson, 'introAudioUrl', descriptor, secureUrl);
        break;
      case 'learning_sentence': {
        const sentence = sentenceFor(descriptor, lesson, 'EN');
        linkField(sentence, 'audioUrl', descriptor, secureUrl);
        break;
      }
      case 'meaning_sentence': {
        const sentence = sentenceFor(descriptor, lesson, 'VI');
        linkField(sentence, 'vietnameseAudioUrl', descriptor, secureUrl);
        break;
      }
      case 'dialogue_transition':
        linkField(lesson, 'dialogueTransitionAudioUrl', descriptor, secureUrl);
        break;
      case 'full_dialogue':
        linkField(lesson, 'fullAudioUrl', descriptor, secureUrl);
        break;
      default:
        throw new Error(`Unsupported audio type: ${descriptor.audioType}`);
    }
    linked += 1;
  }

  await writeFile(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`, 'utf8');
  return linked;
}

function sentenceFor(descriptor, lesson, language) {
  const match = new RegExp(`_S(\\d{3})_${language}$`).exec(descriptor.audioId);
  if (!match) {
    throw new Error(`Invalid sentence audio ID: ${descriptor.audioId}`);
  }
  const sentenceNumber = Number.parseInt(match[1], 10);
  return exactlyOne(
    lesson.sentences,
    (item) => item.number === sentenceNumber,
    `sentence ${sentenceNumber} for ${descriptor.audioId}`,
  );
}

function linkField(target, field, descriptor, secureUrl) {
  const current = target[field];
  if (current !== descriptor.assetUri && current !== secureUrl) {
    throw new Error(
      `${field} for ${descriptor.audioId} no longer matches its local asset URI.`,
    );
  }
  target[field] = secureUrl;
}

function exactlyOne(items, predicate, description) {
  const matches = items.filter(predicate);
  if (matches.length !== 1) {
    throw new Error(`Expected exactly one ${description}; found ${matches.length}.`);
  }
  return matches[0];
}

function normalizeLines(value) {
  return value.replaceAll('\r\n', '\n');
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
