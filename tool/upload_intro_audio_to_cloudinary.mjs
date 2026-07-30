import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(toolDirectory, '..');
const defaultCatalogPath = path.join(
  projectRoot,
  'assets',
  'data',
  'listening_lessons.json',
);
const checkpointPath = path.join(
  projectRoot,
  'build',
  'cloudinary',
  'intro-audio-elevenlabs-upload.json',
);
const publicIdPrefix =
  'speaking-ai/listening/intro-open-elevenlabs/2026-07-29';
const filenamePattern =
  /^(A035|A067|A0810|A1112|A1315)_T(\d{2})_L(\d{2})_OPEN\.mp3$/i;
const ageByPrefix = {
  A035: [3, 5],
  A067: [6, 7],
  A0810: [8, 10],
  A1112: [11, 12],
  A1315: [13, 15],
};

const options = parseArguments(process.argv.slice(2));

try {
  await main();
} catch (error) {
  console.error(`ERROR: ${error instanceof Error ? error.message : error}`);
  process.exitCode = 1;
}

async function main() {
  const audioRoot = path.resolve(requiredValue(options.audioRoot, '--audio-root'));
  const catalogPath = path.resolve(options.catalog ?? defaultCatalogPath);
  const fileEnvironment = options.envFile
    ? parseEnvFile(await readFile(path.resolve(options.envFile), 'utf8'))
    : {};
  const environment = { ...fileEnvironment, ...process.env };
  const cloudinary = {
    cloudName: environment.CLOUDINARY_CLOUD_NAME?.trim(),
    apiKey: environment.CLOUDINARY_API_KEY?.trim(),
    apiSecret: environment.CLOUDINARY_API_SECRET?.trim(),
  };

  if (options.upload && !hasCloudinaryConfig(cloudinary)) {
    throw new Error(
      'Missing CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, or CLOUDINARY_API_SECRET.',
    );
  }

  const catalogSource = await readFile(catalogPath, 'utf8');
  const catalog = JSON.parse(catalogSource);
  const descriptors = await readDescriptors(audioRoot);
  const mapping = mapDescriptorsToLessons(catalog, descriptors);
  const checkpoint = await readCheckpoint(cloudinary.cloudName);
  const pending = descriptors.filter(
    (descriptor) =>
      !isCurrentUpload(checkpoint.uploads[descriptor.publicId], descriptor),
  );
  const totalLessons = countLessons(catalog);
  const totalBytes = descriptors.reduce((sum, item) => sum + item.bytes, 0);

  console.log(`audio_files=${descriptors.length}`);
  console.log(`audio_bytes=${totalBytes}`);
  console.log(`catalog_lessons=${totalLessons}`);
  console.log(`catalog_targets=${mapping.size}`);
  console.log(`catalog_untouched=${totalLessons - mapping.size}`);
  console.log(`checkpoint_entries=${descriptors.length - pending.length}`);
  console.log(`pending_entries=${pending.length}`);
  console.log(`cloud_config=${hasCloudinaryConfig(cloudinary) ? 'present' : 'absent'}`);
  console.log(`mode=${options.upload ? 'upload' : 'dry-run'}`);

  if (!options.upload) {
    validateCatalogReplacement(catalogSource, catalog, mapping, null);
    return;
  }

  if (!checkpoint.cloudName) {
    checkpoint.cloudName = cloudinary.cloudName;
  }
  if (pending.length > 0) {
    await uploadAll(pending, checkpoint, cloudinary);
  }

  const allComplete = descriptors.every((descriptor) =>
    isCurrentUpload(checkpoint.uploads[descriptor.publicId], descriptor),
  );
  if (!allComplete) {
    throw new Error('Not all intro audio files have a current Cloudinary upload.');
  }

  if (options.verify) {
    await verifyUploads(descriptors, checkpoint);
  }

  if (options.writeCatalog) {
    const updatedSource = validateCatalogReplacement(
      catalogSource,
      catalog,
      mapping,
      checkpoint,
    );
    await writeFile(catalogPath, updatedSource, 'utf8');
    console.log(`catalog_linked_urls=${mapping.size}`);
  }

  console.log(`upload_complete=${allComplete}`);
  console.log(
    `checkpoint=${path.relative(projectRoot, checkpointPath).replaceAll('\\', '/')}`,
  );
}

function parseArguments(argumentsList) {
  const result = {
    audioRoot: undefined,
    catalog: undefined,
    concurrency: 4,
    envFile: undefined,
    upload: false,
    verify: false,
    writeCatalog: false,
  };
  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    switch (argument) {
      case '--audio-root':
        result.audioRoot = requiredValue(argumentsList[++index], '--audio-root');
        break;
      case '--catalog':
        result.catalog = requiredValue(argumentsList[++index], '--catalog');
        break;
      case '--concurrency':
        result.concurrency = positiveInteger(
          argumentsList[++index],
          '--concurrency',
        );
        break;
      case '--env-file':
        result.envFile = requiredValue(argumentsList[++index], '--env-file');
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
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }
  if (!result.upload && (result.verify || result.writeCatalog)) {
    throw new Error('--verify and --write-catalog require --upload.');
  }
  return result;
}

function requiredValue(value, argumentName) {
  if (!value || value.startsWith('--')) {
    throw new Error(`${argumentName} requires a value.`);
  }
  return value;
}

function positiveInteger(value, argumentName) {
  const parsed = Number.parseInt(requiredValue(value, argumentName), 10);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new Error(`${argumentName} must be a positive integer.`);
  }
  return parsed;
}

function parseEnvFile(contents) {
  const values = {};
  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const normalized = line.startsWith('export ') ? line.slice(7) : line;
    const separator = normalized.indexOf('=');
    if (separator < 1) continue;
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

async function readDescriptors(audioRoot) {
  const entries = await readdir(audioRoot, { withFileTypes: true });
  const filenames = entries
    .filter((entry) => entry.isFile() && /_OPEN\.mp3$/i.test(entry.name))
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right));
  if (filenames.length === 0) {
    throw new Error(`No *_OPEN.mp3 files found in ${audioRoot}.`);
  }

  const publicIds = new Set();
  const descriptors = [];
  for (const filename of filenames) {
    const match = filenamePattern.exec(filename);
    if (!match) throw new Error(`Unexpected intro filename: ${filename}`);
    const prefix = match[1].toUpperCase();
    const [ageStart, ageEnd] = ageByPrefix[prefix];
    const filePath = path.join(audioRoot, filename);
    const fileStats = await stat(filePath);
    const contents = await readFile(filePath);
    const basename = filename.replace(/\.mp3$/i, '');
    const publicId = `${publicIdPrefix}/${basename}`;
    if (publicIds.has(publicId)) {
      throw new Error(`Duplicate Cloudinary public ID: ${publicId}`);
    }
    publicIds.add(publicId);
    descriptors.push({
      ageEnd,
      ageStart,
      bytes: fileStats.size,
      code: basename.replace(/_OPEN$/i, ''),
      filePath,
      filename,
      lessonNumber: Number.parseInt(match[3], 10),
      publicId,
      sha256: createHash('sha256').update(contents).digest('hex'),
      topicNumber: Number.parseInt(match[2], 10),
    });
  }
  return descriptors;
}

function mapDescriptorsToLessons(catalog, descriptors) {
  if (!Array.isArray(catalog?.groups)) {
    throw new Error('Catalog does not contain a groups array.');
  }
  const mapping = new Map();
  for (const descriptor of descriptors) {
    const group = catalog.groups.find(
      (item) =>
        Number(item.startAge) === descriptor.ageStart &&
        Number(item.endAge) === descriptor.ageEnd,
    );
    const topic = group?.topics?.find(
      (item) => Number(item.number) === descriptor.topicNumber,
    );
    const candidates = (topic?.lessons ?? []).filter(
      (item) => Number(item.number) === descriptor.lessonNumber,
    );
    if (candidates.length !== 1) {
      throw new Error(
        `${descriptor.filename} matched ${candidates.length} catalog lessons.`,
      );
    }
    if (mapping.has(candidates[0])) {
      throw new Error(`Multiple audio files matched ${descriptor.code}.`);
    }
    mapping.set(candidates[0], descriptor);
  }
  return mapping;
}

function countLessons(catalog) {
  return catalog.groups.reduce(
    (groupTotal, group) =>
      groupTotal +
      group.topics.reduce(
        (topicTotal, topic) => topicTotal + (topic.lessons?.length ?? 0),
        0,
      ),
    0,
  );
}

async function readCheckpoint(cloudName) {
  let checkpoint;
  try {
    checkpoint = JSON.parse(await readFile(checkpointPath, 'utf8'));
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
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
    !checkpoint.uploads ||
    typeof checkpoint.uploads !== 'object'
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
  let completed = 0;
  let checkpointWrite = Promise.resolve();
  const persist = () => {
    checkpointWrite = checkpointWrite.then(() =>
      writeFile(checkpointPath, `${JSON.stringify(checkpoint, null, 2)}\n`, 'utf8'),
    );
    return checkpointWrite;
  };
  const worker = async () => {
    while (true) {
      const index = nextIndex++;
      if (index >= descriptors.length) return;
      const descriptor = descriptors[index];
      const payload = await uploadWithRetry(descriptor, cloudinary);
      checkpoint.uploads[descriptor.publicId] = {
        bytes: payload.bytes,
        format: payload.format,
        publicId: payload.public_id,
        resourceType: payload.resource_type,
        secureUrl: payload.secure_url,
        sha256: descriptor.sha256,
        uploadedAt: new Date().toISOString(),
        version: payload.version,
      };
      await persist();
      completed += 1;
      if (completed % 10 === 0 || completed === descriptors.length) {
        console.log(`uploaded=${completed}/${descriptors.length}`);
      }
    }
  };
  const workerCount = Math.min(options.concurrency, descriptors.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
  await checkpointWrite;
}

async function uploadWithRetry(descriptor, cloudinary) {
  let lastError;
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      return await uploadOne(descriptor, cloudinary);
    } catch (error) {
      lastError = error;
      const retryable = !error.status || error.status === 429 || error.status >= 500;
      if (!retryable || attempt === 4) break;
      await delay(750 * 2 ** (attempt - 1));
    }
  }
  throw new Error(
    `Upload failed for ${descriptor.filename}: ${lastError?.message ?? lastError}`,
  );
}

async function uploadOne(descriptor, cloudinary) {
  const signedParameters = {
    overwrite: 'true',
    public_id: descriptor.publicId,
    tags: 'speaking-ai,listening,intro,elevenlabs',
    timestamp: Math.floor(Date.now() / 1000).toString(),
  };
  const signature = signCloudinaryParameters(
    signedParameters,
    cloudinary.apiSecret,
  );
  const form = new FormData();
  form.append(
    'file',
    new Blob([await readFile(descriptor.filePath)], { type: 'audio/mpeg' }),
    descriptor.filename,
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
    throw new Error(`Unexpected Cloudinary response for ${descriptor.filename}.`);
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

async function verifyUploads(descriptors, checkpoint) {
  let nextIndex = 0;
  let verified = 0;
  const worker = async () => {
    while (true) {
      const index = nextIndex++;
      if (index >= descriptors.length) return;
      const descriptor = descriptors[index];
      const upload = checkpoint.uploads[descriptor.publicId];
      await verifyUrlWithRetry(upload.secureUrl, descriptor.filename);
      verified += 1;
      if (verified % 20 === 0 || verified === descriptors.length) {
        console.log(`verified=${verified}/${descriptors.length}`);
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(8, descriptors.length) }, () => worker()));
}

async function verifyUrlWithRetry(url, filename) {
  let lastStatus;
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: { Range: 'bytes=0-0' },
        signal: AbortSignal.timeout(30_000),
      });
      lastStatus = response.status;
      await response.body?.cancel();
      if (response.ok) return;
    } catch (error) {
      lastStatus = error instanceof Error ? error.message : String(error);
    }
    if (attempt < 4) await delay(500 * 2 ** (attempt - 1));
  }
  throw new Error(`Delivery verification failed for ${filename}: ${lastStatus}`);
}

function validateCatalogReplacement(source, catalog, mapping, checkpoint) {
  const fields = [];
  collectIntroFields(catalog, mapping, fields);
  const fieldPattern =
    /^([ \t]*"introAudioUrl"[ \t]*:[ \t]*)(null|"(?:\\.|[^"\\])*")([ \t]*,?[ \t]*)$/gm;
  let fieldIndex = 0;
  let replacementCount = 0;
  const result = source.replace(fieldPattern, (whole, prefix, literal, suffix) => {
    const field = fields[fieldIndex++];
    if (!field) throw new Error('Catalog contains an unexpected introAudioUrl field.');
    if (JSON.parse(literal) !== field.currentValue) {
      throw new Error(`Catalog field order mismatch at ${field.path}.`);
    }
    if (!field.descriptor) return whole;
    replacementCount += 1;
    if (!checkpoint) return whole;
    const upload = checkpoint.uploads[field.descriptor.publicId];
    if (!isCurrentUpload(upload, field.descriptor)) {
      throw new Error(`Missing current upload for ${field.descriptor.filename}.`);
    }
    return `${prefix}${JSON.stringify(upload.secureUrl)}${suffix}`;
  });
  if (fieldIndex !== fields.length) {
    throw new Error(
      `Found ${fieldIndex} textual introAudioUrl fields for ${fields.length} catalog fields.`,
    );
  }
  if (replacementCount !== mapping.size) {
    throw new Error(
      `Prepared ${replacementCount} replacements for ${mapping.size} mapped lessons.`,
    );
  }
  return result;
}

function collectIntroFields(value, mapping, fields, currentPath = 'root') {
  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      collectIntroFields(item, mapping, fields, `${currentPath}[${index}]`),
    );
    return;
  }
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    const childPath = `${currentPath}.${key}`;
    if (key === 'introAudioUrl') {
      fields.push({
        currentValue: child,
        descriptor: mapping.get(value),
        path: childPath,
      });
    }
    collectIntroFields(child, mapping, fields, childPath);
  }
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
