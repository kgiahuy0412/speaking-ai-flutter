// Imports the six September HOMI CSV packs without changing curriculum IDs.
// Usage: node tool/import_homi_audio.mjs <source-directory>
import fs from 'node:fs';
import path from 'node:path';

const source = path.resolve(process.argv[2] ?? 'D:/Code/HuaMei/App_noi/Tao_audio_11th9');
const assetRoot = 'assets/audio/homi_v4';
const catalogPath = 'assets/data/listening_lessons.json';
const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
const lessons = catalog.groups.flatMap(g => g.topics.flatMap(t => t.lessons.map(l => ({ lesson: l, age: `${g.startAge}-${g.endAge}`, topic: t.number, level: t.levelNumber }))));
const targets = new Map(lessons.flatMap(({ lesson }) => lesson.sentences.map(s => [s.id, s])));
const challenges = new Map(lessons.flatMap(({ lesson }) => lesson.challengeBank.map(q => [q.id, q])));
const missions = new Map(catalog.groups.flatMap(g => g.levels.flatMap(l => l.missionBank.map(q => [q.id, q]))));
const clips = [], sequences = [], missing = [], copies = [];
const norm = s => (s ?? '').normalize('NFC').replace(/\[(?:SFX|MUSIC|BGM|SOUND|AUDIO|FX)\s*:[^\]]+\]/gi, '').replace(/\s+/g, ' ').trim();

function readCsv(file) {
  const input = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  const records = []; let row = [], cell = '', quoted = false;
  for (let i = 0; i < input.length; i++) {
    const c = input[i];
    if (c === '"') {
      if (quoted && input[i + 1] === '"') { cell += '"'; i++; } else quoted = !quoted;
    } else if (c === ',' && !quoted) { row.push(cell); cell = ''; }
    else if (c === '\n' && !quoted) { row.push(cell.replace(/\r$/, '')); if (row.some(Boolean)) records.push(row); row = []; cell = ''; }
    else cell += c;
  }
  if (cell || row.length) { row.push(cell.replace(/\r$/, '')); records.push(row); }
  const headers = records.shift();
  return records.map(r => Object.fromEntries(headers.map((h, i) => [h, r[i] ?? ''])));
}
function expectText(actual, expected, id) {
  if (norm(actual) !== norm(expected)) throw new Error(`Text mismatch for ${id}: ${actual} / ${expected}`);
}
function add(dir, relative, id, kind, text, locale = 'vi-VN', extra = {}) {
  if (clips.some(c => c.id === id)) throw new Error(`Duplicate audio ID: ${id}`);
  const sourceFile = path.resolve(dir, relative);
  if (!sourceFile.startsWith(path.resolve(dir) + path.sep)) throw new Error(`Unsafe path: ${relative}`);
  if (!fs.statSync(sourceFile).size) throw new Error(`Empty audio: ${sourceFile}`);
  const asset = `${assetRoot}/${kind}/${id}.mp3`;
  clips.push({ id, asset, kind, text: norm(text), locale, ...extra });
  copies.push({ sourceFile, asset });
  return `asset:///${asset}`;
}
const packs = fs.readdirSync(source).filter(d => fs.statSync(path.join(source, d)).isDirectory());
for (const prefix of ['01_', '02_', '03_', '05_', '06_', '07_']) {
  const name = packs.find(d => d.startsWith(prefix));
  if (!name) throw new Error(`Missing pack ${prefix}`);
  const dir = path.join(source, name);
  for (const r of readCsv(path.join(dir, 'manifest.csv'))) {
    if (prefix === '01_') {
      const id = r.kind === 'static' ? r.cue_id : r.kind === 'dynamic_lesson_name' ? `${r.cue_id}_${r.lesson_table}` : `${r.cue_id}_${r.variable_value.replace(/[^a-zA-Z0-9]+/g, '_')}`;
      const text = r.source_template.replace(/^\[DYNAMIC\]\s*/, '').replace(/\[([^\]]+)\]/g, (_, variable) => variable === r.variable_name ? r.variable_value : `[${variable}]`);
      if (/\[[A-Z_]+\]/.test(text)) throw new Error(`Unresolved system cue ${id}: ${text}`);
      add(dir, r.relative_path, id, 'system', text, 'vi-VN', { cue: r.cue_id, variable: r.variable_value });
    } else if (prefix === '02_') {
      add(dir, r.relative_path, `FEEDBACK_${r.age.replaceAll('-', '_')}_${r.state_code}_${r.variant_index}`, 'feedback', r.text, r.language === 'en' ? 'en-US' : 'vi-VN', { age: r.age, state: r.state_code });
    } else if (prefix === '03_') {
      const match = lessons.find(l => l.age === r.age && l.level === Number(r.level) && l.topic === Number(r.topic) && l.lesson.titleEn === r.lesson)?.lesson;
      if (!match) throw new Error(`Unknown hook lesson ${r.lesson}`);
      expectText(match.entry.text, r.originalAudio, match.code);
      add(dir, r.relativePath, `${match.code}_ENTRY`, 'hook', match.entry.text, 'vi-VN', { sfxEmbedded: Boolean(r.sfx) });
    } else if (prefix === '05_') {
      const target = targets.get(r.target_id), language = r.language === 'en' ? 'EN' : 'VI';
      if (!target) throw new Error(`Unknown target ${r.target_id}`);
      expectText(target[r.language === 'en' ? 'english' : 'vietnamese'], r.text, r.target_id);
      const uri = add(dir, r.relative_path, `${r.target_id}_${language}`, 'core', r.text, r.language === 'en' ? 'en-US' : 'vi-VN');
      target[r.language === 'en' ? 'audioUrl' : 'vietnameseAudioUrl'] = uri;
    } else {
      const mission = prefix === '07_', id = mission ? r.mission_id : r.question_id;
      const question = (mission ? missions : challenges).get(id);
      if (!question) throw new Error(`Unknown question ${id}`);
      expectText(question.correctAnswer, r.correct_reference, id);
      if ((question.targetId ?? question.coverageTargetId) !== r.target_ref.split(' ')[0]) throw new Error(`Wrong target for ${id}`);
      const text = r.original_text ?? r.text;
      expectText(r.role === 'prompt' ? question.prompt : question.choices[Number(r.role.slice(-1)) - 1], text, id);
      add(dir, r.relative_path, `${id}_${r.role.toUpperCase()}`, mission ? 'mission' : 'challenge', text, r.role === 'prompt' ? 'vi-VN' : 'en-US', { sfxEmbedded: r.sfx_embedded === 'true' });
    }
  }
  const sfxDir = path.join(dir, '_sfx_assets');
  if (fs.existsSync(sfxDir)) {
    for (const filename of fs.readdirSync(sfxDir).filter(f => f.endsWith('.mp3')).sort()) {
      const id = path.parse(filename).name;
      if (!clips.some(c => c.id === id)) add(dir, `_sfx_assets/${filename}`, id, 'sfx', '', 'und');
    }
  }
}
for (const { lesson, topic } of lessons) {
  // Match the existing visible intro exactly while playing independently
  // addressable clips. Missing clips remain individual TTS segments.
  const parts = [];
  if (lesson.number === 1) parts.push({ text: `Chủ đề ${topic}.` });
  parts.push({ text: `${lesson.number === 1 ? 'Bài đầu tiên là' : 'Bài này là'} ${lesson.titleEn}.` });
  parts.push({ text: lesson.entry.text, audioId: `${lesson.code}_ENTRY` });
  parts.push({ text: 'Bắt đầu nhé.', audioId: 'DETAIL_TRANSITION' });
  sequences.push({ text: parts.map(p => p.text).join(' '), parts });
  if (!clips.some(c => c.id === `${lesson.code}_ENTRY`)) missing.push({ kind: 'entry', id: `${lesson.code}_ENTRY`, text: lesson.entry.text });
  for (const s of lesson.sentences) {
    for (const [field, suffix] of [['english', 'EN'], ['vietnamese', 'VI']]) {
      if (!clips.some(c => c.id === `${s.id}_${suffix}`)) missing.push({ kind: 'core', id: `${s.id}_${suffix}`, text: s[field] });
    }
  }
}
// The navigation controller announces these together before opening its mic.
for (let level = 1; level <= 3; level++) {
  const count = level === 3 ? 4 : 3;
  const parts = [{ text: `Bắt đầu Level ${level}.` }, { text: `Có ${count} Chủ đề. Bạn muốn học Chủ đề số mấy?` }];
  sequences.push({ text: parts.map(p => p.text).join(' '), parts });
}
// Validation finishes before copying any files or updating application data.
for (const { sourceFile, asset } of copies) {
  fs.mkdirSync(path.dirname(asset), { recursive: true });
  fs.copyFileSync(sourceFile, asset);
}
const audioIndex = { schemaVersion: 1, packVersion: '2026-09-11', playbackRate: 1, clips, sequences, missing };
fs.writeFileSync('assets/data/homi_audio_index.json', JSON.stringify(audioIndex, null, 2) + '\n');
catalog.audioProvider = 'homi-recorded-2026-09-11-with-tts-fallback';
fs.writeFileSync(catalogPath, JSON.stringify(catalog, null, 2) + '\n');
const handoffPath = 'assets/data/listening_audio_manifest_v4.json';
const handoff = JSON.parse(fs.readFileSync(handoffPath, 'utf8'));
const byId = new Map(clips.map(c => [c.id, c]));
for (const entry of handoff.entries) {
  const clip = byId.get(entry.audioId);
  if (clip) { entry.audioUrl = `asset:///${clip.asset}`; entry.qaStatus = 'READY_SOURCE_AUDIO'; }
}
fs.writeFileSync(handoffPath, JSON.stringify(handoff, null, 2) + '\n');
console.log(JSON.stringify({ imported: clips.length, sequences: sequences.length, missing, bytes: copies.reduce((n, c) => n + fs.statSync(c.asset).size, 0) }, null, 2));
