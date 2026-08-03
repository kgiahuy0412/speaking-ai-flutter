import { createHash } from 'node:crypto';
import { mkdir, readdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(toolDirectory, '..');
const options = parseArguments(process.argv.slice(2));
const datasetProfiles = {
  a035: {
    checkpointName: 'sentence-audio-elevenlabs-upload.json',
    expectedAudioFiles: 112,
    filenamePattern: /^A035_T(\d{2})_L(\d{2})_S(\d{3})_(EN|VI)\.mp3$/i,
    publicIdPrefix: 'speaking-ai/listening/sentence-elevenlabs/2026-07-29',
  },
  'song-lessons': {
    checkpointName: 'song-lesson-sentence-audio-elevenlabs-upload.json',
    expectedAudioFiles: 68,
    filenamePattern:
      /^(A06_07_T0[123]|A08_10_T0[45])_S(\d{3})_(EN|VI)\.mp3$/i,
    publicIdPrefix:
      'speaking-ai/listening/song-lesson-sentence-elevenlabs/2026-07-29',
    sourceLessons: {
      A06_07_T01: { lessonId: 'a067_t05_l02', expectedFiles: 16 },
      A06_07_T02: { lessonId: 'a067_t07_l02', expectedFiles: 12 },
      A06_07_T03: { lessonId: 'a067_t08_l02', expectedFiles: 16 },
      A08_10_T04: { lessonId: 'a0810_t03_l02', expectedFiles: 12 },
      A08_10_T05: { lessonId: 'a0810_t04_l02', expectedFiles: 12 },
    },
  },
};
const datasetProfile = datasetProfiles[options.dataset];
if (!datasetProfile) throw new Error(`Unknown dataset: ${options.dataset}`);
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
  datasetProfile.checkpointName,
);
const publicIdPrefix = datasetProfile.publicIdPrefix;
const filenamePattern = datasetProfile.filenamePattern;

try {
  await main();
} catch (error) {
  console.error(`ERROR: ${error instanceof Error ? error.message : error}`);
  process.exitCode = 1;
}

async function main() {
  const audioRoot = path.resolve(requiredValue(options.audioRoot, '--audio-root'));
  const catalogPath = path.resolve(options.catalog ?? defaultCatalogPath);
  const environment = {
    ...(options.envFile
      ? parseEnvFile(await readFile(path.resolve(options.envFile), 'utf8'))
      : {}),
    ...process.env,
  };
  const cloudinary = {
    cloudName: environment.CLOUDINARY_CLOUD_NAME?.trim(),
    apiKey: environment.CLOUDINARY_API_KEY?.trim(),
    apiSecret: environment.CLOUDINARY_API_SECRET?.trim(),
  };
  if (options.upload && !hasCloudinaryConfig(cloudinary)) {
    throw new Error('Cloudinary configuration is incomplete.');
  }

  const source = await readFile(catalogPath, 'utf8');
  const catalog = JSON.parse(source);
  const descriptors = await readDescriptors(audioRoot);
  const mapping = mapDescriptorsToSentences(catalog, descriptors);
  const checkpoint = await readCheckpoint(cloudinary.cloudName);
  const pending = descriptors.filter(
    (descriptor) =>
      !isCurrentUpload(checkpoint.uploads[descriptor.publicId], descriptor),
  );
  const englishCount = descriptors.filter((item) => item.language === 'EN').length;
  const vietnameseCount = descriptors.length - englishCount;

  console.log(`audio_files=${descriptors.length}`);
  console.log(`english_files=${englishCount}`);
  console.log(`vietnamese_files=${vietnameseCount}`);
  console.log(`mapped_sentence_fields=${mapping.fieldCount}`);
  console.log(`pending_entries=${pending.length}`);
  console.log(`cloud_config=${hasCloudinaryConfig(cloudinary) ? 'present' : 'absent'}`);
  console.log(`mode=${options.upload ? 'upload' : 'dry-run'}`);

  validateCatalogReplacement(source, catalog, mapping.bySentence, null);
  if (!options.upload) return;

  if (!checkpoint.cloudName) checkpoint.cloudName = cloudinary.cloudName;
  if (pending.length > 0) {
    await uploadAll(pending, checkpoint, cloudinary);
  }
  const allComplete = descriptors.every((descriptor) =>
    isCurrentUpload(checkpoint.uploads[descriptor.publicId], descriptor),
  );
  if (!allComplete) {
    throw new Error('Not all sentence audio files have a current upload.');
  }
  if (options.verify) await verifyUploads(descriptors, checkpoint);
  if (options.writeCatalog) {
    const updated = validateCatalogReplacement(
      source,
      catalog,
      mapping.bySentence,
      checkpoint,
    );
    await writeFile(catalogPath, updated, 'utf8');
    console.log(`catalog_linked_urls=${mapping.fieldCount}`);
  }
  console.log(`upload_complete=${allComplete}`);
  console.log(
    `checkpoint=${path.relative(projectRoot, checkpointPath).replaceAll('\\', '/')}`,
  );
}

function parseArguments(args) {
  const result = {
    audioRoot: undefined,
    catalog: undefined,
    concurrency: 4,
    dataset: 'a035',
    envFile: undefined,
    upload: false,
    verify: false,
    writeCatalog: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    switch (args[index]) {
      case '--audio-root':
        result.audioRoot = requiredValue(args[++index], '--audio-root');
        break;
      case '--catalog':
        result.catalog = requiredValue(args[++index], '--catalog');
        break;
      case '--concurrency':
        result.concurrency = positiveInteger(args[++index], '--concurrency');
        break;
      case '--dataset':
        result.dataset = requiredValue(args[++index], '--dataset');
        break;
      case '--env-file':
        result.envFile = requiredValue(args[++index], '--env-file');
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
        throw new Error(`Unknown argument: ${args[index]}`);
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
  const result = {};
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
    result[key] = value;
  }
  return result;
}

function hasCloudinaryConfig(config) {
  return Boolean(config.cloudName && config.apiKey && config.apiSecret);
}

async function readDescriptors(audioRoot) {
  if (options.dataset === 'song-lessons') {
    return readSongLessonDescriptors(audioRoot);
  }
  const reportPath = path.join(audioRoot, 'generation_report.json');
  const report = JSON.parse(await readFile(reportPath, 'utf8'));
  if (
    report.status !== 'complete' ||
    report.audioFiles !== datasetProfile.expectedAudioFiles ||
    !Array.isArray(report.files)
  ) {
    throw new Error('The sentence audio generation report is incomplete.');
  }
  const descriptors = [];
  const publicIds = new Set();
  for (const entry of report.files) {
    if (entry.status !== 'OK') {
      throw new Error(`${entry.fileName ?? 'An audio file'} did not pass generation QA.`);
    }
    const match = filenamePattern.exec(entry.fileName ?? '');
    if (!match) throw new Error(`Unexpected filename: ${entry.fileName}`);
    const expectedLanguage = match[4].toUpperCase() === 'EN' ? 'en' : 'vi';
    if (entry.language !== expectedLanguage) {
      throw new Error(`Language mismatch for ${entry.fileName}.`);
    }
    const filePath = path.resolve(audioRoot, ...entry.relativePath.split(/[\\/]/));
    const safeRoot = `${path.resolve(audioRoot)}${path.sep}`;
    if (!filePath.startsWith(safeRoot)) {
      throw new Error(`Unsafe relative path: ${entry.relativePath}`);
    }
    const fileStats = await stat(filePath);
    const contents = await readFile(filePath);
    if (!fileStats.isFile() || fileStats.size !== entry.bytes) {
      throw new Error(`File size mismatch for ${entry.fileName}.`);
    }
    const basename = entry.fileName.replace(/\.mp3$/i, '');
    const publicId = `${publicIdPrefix}/${basename}`;
    if (publicIds.has(publicId)) throw new Error(`Duplicate file: ${entry.fileName}`);
    publicIds.add(publicId);
    descriptors.push({
      bytes: fileStats.size,
      filePath,
      filename: entry.fileName,
      language: match[4].toUpperCase(),
      lessonNumber: Number.parseInt(match[2], 10),
      publicId,
      sentenceNumber: Number.parseInt(match[3], 10),
      sha256: createHash('sha256').update(contents).digest('hex'),
      sourceText: entry.text,
      topicNumber: Number.parseInt(match[1], 10),
    });
  }
  if (descriptors.length !== datasetProfile.expectedAudioFiles) {
    throw new Error(
      `Expected ${datasetProfile.expectedAudioFiles} audio files, found ${descriptors.length}.`,
    );
  }
  return descriptors.sort((left, right) =>
    left.filename.localeCompare(right.filename),
  );
}

async function readSongLessonDescriptors(audioRoot) {
  const filePaths = await listFilesRecursively(audioRoot);
  const audioPaths = filePaths.filter((filePath) => /\.mp3$/i.test(filePath));
  if (audioPaths.length !== datasetProfile.expectedAudioFiles) {
    throw new Error(
      `Expected ${datasetProfile.expectedAudioFiles} audio files, found ${audioPaths.length}.`,
    );
  }
  const descriptors = [];
  const publicIds = new Set();
  const sourceCounts = new Map();
  for (const filePath of audioPaths) {
    const filename = path.basename(filePath);
    const match = filenamePattern.exec(filename);
    if (!match) throw new Error(`Unexpected filename: ${filename}`);
    const sourceCode = match[1].toUpperCase();
    if (path.basename(path.dirname(filePath)).toUpperCase() !== sourceCode) {
      throw new Error(`${filename} is not inside its expected source directory.`);
    }
    const sourceLesson = datasetProfile.sourceLessons[sourceCode];
    if (!sourceLesson) throw new Error(`Unsupported source lesson: ${sourceCode}`);
    const contents = await readFile(filePath);
    const publicId = `${publicIdPrefix}/${filename.replace(/\.mp3$/i, '')}`;
    if (publicIds.has(publicId)) throw new Error(`Duplicate file: ${filename}`);
    publicIds.add(publicId);
    sourceCounts.set(sourceCode, (sourceCounts.get(sourceCode) ?? 0) + 1);
    descriptors.push({
      bytes: contents.length,
      filePath,
      filename,
      language: match[3].toUpperCase(),
      lessonId: sourceLesson.lessonId,
      publicId,
      sentenceNumber: Number.parseInt(match[2], 10),
      sha256: createHash('sha256').update(contents).digest('hex'),
      sourceCode,
    });
  }
  for (const [sourceCode, sourceLesson] of Object.entries(
    datasetProfile.sourceLessons,
  )) {
    const actual = sourceCounts.get(sourceCode) ?? 0;
    if (actual !== sourceLesson.expectedFiles) {
      throw new Error(
        `${sourceCode} has ${actual} files instead of ${sourceLesson.expectedFiles}.`,
      );
    }
  }
  return descriptors.sort((left, right) =>
    left.filename.localeCompare(right.filename),
  );
}

async function listFilesRecursively(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map((entry) => {
      const entryPath = path.join(directory, entry.name);
      return entry.isDirectory() ? listFilesRecursively(entryPath) : [entryPath];
    }),
  );
  return nested.flat();
}

function mapDescriptorsToSentences(catalog, descriptors) {
  if (options.dataset === 'song-lessons') {
    return mapSongLessonDescriptors(catalog, descriptors);
  }
  const group = catalog.groups?.find(
    (candidate) => candidate.startAge === 3 && candidate.endAge === 5,
  );
  if (!group) throw new Error('The 3-5 age group is missing from the catalog.');
  const bySentence = new Map();
  for (const descriptor of descriptors) {
    const topic = group.topics.find(
      (candidate) => Number(candidate.number) === descriptor.topicNumber,
    );
    const lesson = topic?.lessons?.find(
      (candidate) => Number(candidate.number) === descriptor.lessonNumber,
    );
    const sentence = lesson?.sentences?.find(
      (candidate) => Number(candidate.number) === descriptor.sentenceNumber,
    );
    if (!sentence) {
      throw new Error(`${descriptor.filename} did not match a catalog sentence.`);
    }
    const expectedText =
      descriptor.language === 'EN' ? sentence.english : sentence.vietnamese;
    if (descriptor.sourceText !== expectedText) {
      throw new Error(`Text mismatch for ${descriptor.filename}.`);
    }
    const fieldName =
      descriptor.language === 'EN' ? 'audioUrl' : 'vietnameseAudioUrl';
    const fields = bySentence.get(sentence) ?? {};
    if (fields[fieldName]) {
      throw new Error(`Duplicate ${fieldName} for ${descriptor.filename}.`);
    }
    fields[fieldName] = descriptor;
    bySentence.set(sentence, fields);
  }
  for (const [sentence, fields] of bySentence) {
    if (!fields.audioUrl || !fields.vietnameseAudioUrl) {
      throw new Error(`Sentence ${sentence.id} does not have both languages.`);
    }
  }
  return { bySentence, fieldCount: descriptors.length };
}

function mapSongLessonDescriptors(catalog, descriptors) {
  const lessons = new Map();
  for (const group of catalog.groups ?? []) {
    for (const topic of group.topics ?? []) {
      for (const lesson of topic.lessons ?? []) {
        if (lessons.has(lesson.id)) throw new Error(`Duplicate lesson ID: ${lesson.id}`);
        lessons.set(lesson.id, lesson);
      }
    }
  }
  const bySentence = new Map();
  for (const descriptor of descriptors) {
    const lesson = lessons.get(descriptor.lessonId);
    const sentence = lesson?.sentences?.find(
      (candidate) => Number(candidate.number) === descriptor.sentenceNumber,
    );
    if (!sentence) {
      throw new Error(`${descriptor.filename} did not match a catalog sentence.`);
    }
    const fieldName =
      descriptor.language === 'EN' ? 'audioUrl' : 'vietnameseAudioUrl';
    const fields = bySentence.get(sentence) ?? {};
    if (fields[fieldName]) {
      throw new Error(`Duplicate ${fieldName} for ${descriptor.filename}.`);
    }
    fields[fieldName] = descriptor;
    bySentence.set(sentence, fields);
  }
  for (const [sentence, fields] of bySentence) {
    if (!fields.audioUrl || !fields.vietnameseAudioUrl) {
      throw new Error(`Sentence ${sentence.id} does not have both languages.`);
    }
  }
  return { bySentence, fieldCount: descriptors.length };
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
    throw new Error('The checkpoint belongs to another Cloudinary cloud.');
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
  await Promise.all(
    Array.from(
      { length: Math.min(options.concurrency, descriptors.length) },
      () => worker(),
    ),
  );
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
  const parameters = {
    overwrite: 'true',
    public_id: descriptor.publicId,
    tags: 'speaking-ai,listening,sentence,elevenlabs',
    timestamp: Math.floor(Date.now() / 1000).toString(),
  };
  const form = new FormData();
  form.append(
    'file',
    new Blob([await readFile(descriptor.filePath)], { type: 'audio/mpeg' }),
    descriptor.filename,
  );
  form.append('api_key', cloudinary.apiKey);
  for (const [key, value] of Object.entries(parameters)) form.append(key, value);
  form.append('signature', signCloudinaryParameters(parameters, cloudinary.apiSecret));
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
    typeof payload.secure_url !== 'string'
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
  await Promise.all(
    Array.from({ length: Math.min(8, descriptors.length) }, () => worker()),
  );
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
  throw new Error(`Verification failed for ${filename}: ${lastStatus}`);
}

function validateCatalogReplacement(source, catalog, bySentence, checkpoint) {
  const fields = [];
  collectAudioFields(catalog, bySentence, fields);
  const pattern =
    /^([ \t]*"(audioUrl|vietnameseAudioUrl)"[ \t]*:[ \t]*)(null|"(?:\\.|[^"\\])*")([ \t]*,?[ \t]*)$/gm;
  let fieldIndex = 0;
  let replacements = 0;
  const result = source.replace(
    pattern,
    (whole, prefix, fieldName, literal, suffix) => {
      const field = fields[fieldIndex++];
      if (!field) throw new Error('Unexpected sentence audio field in catalog.');
      if (field.fieldName !== fieldName || JSON.parse(literal) !== field.currentValue) {
        throw new Error(`Catalog field order mismatch at ${field.path}.`);
      }
      const descriptor = field.descriptor;
      if (!descriptor) return whole;
      replacements += 1;
      if (!checkpoint) return whole;
      const upload = checkpoint.uploads[descriptor.publicId];
      if (!isCurrentUpload(upload, descriptor)) {
        throw new Error(`Missing upload for ${descriptor.filename}.`);
      }
      return `${prefix}${JSON.stringify(upload.secureUrl)}${suffix}`;
    },
  );
  if (fieldIndex !== fields.length) {
    throw new Error(`Found ${fieldIndex} textual fields for ${fields.length} catalog fields.`);
  }
  const expectedReplacements = [...bySentence.values()].reduce(
    (total, fieldsForSentence) =>
      total + Number(Boolean(fieldsForSentence.audioUrl)) +
      Number(Boolean(fieldsForSentence.vietnameseAudioUrl)),
    0,
  );
  if (replacements !== expectedReplacements) {
    throw new Error(
      `Prepared ${replacements} replacements instead of ${expectedReplacements}.`,
    );
  }
  return result;
}

function collectAudioFields(value, bySentence, fields, currentPath = 'root') {
  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      collectAudioFields(item, bySentence, fields, `${currentPath}[${index}]`),
    );
    return;
  }
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    const childPath = `${currentPath}.${key}`;
    if (key === 'audioUrl' || key === 'vietnameseAudioUrl') {
      fields.push({
        currentValue: child,
        descriptor: bySentence.get(value)?.[key],
        fieldName: key,
        path: childPath,
      });
    }
    collectAudioFields(child, bySentence, fields, childPath);
  }
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
