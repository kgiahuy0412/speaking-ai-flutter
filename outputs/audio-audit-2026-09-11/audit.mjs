import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const pack = 'D:/Code/HuaMei/App_noi/Tao_audio_11th9';
const source = fs.readFileSync('C:/Users/DELL/Downloads/AIV0_HOMI_Audio_TTS_FINAL_Tich_hop.txt', 'utf8');
const catalog = JSON.parse(fs.readFileSync('assets/data/listening_lessons.json', 'utf8'));
const manifest = JSON.parse(fs.readFileSync('assets/data/listening_audio_manifest_v4.json', 'utf8'));
function csv(file) {
  const input = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  const records = []; let row = [], cell = '', quoted = false;
  for (let i = 0; i < input.length; i++) {
    const c = input[i];
    if (c === '"') {
      if (quoted && input[i + 1] === '"') { cell += '"'; i++; }
      else quoted = !quoted;
    } else if (c === ',' && !quoted) { row.push(cell); cell = ''; }
    else if (c === '\n' && !quoted) { row.push(cell.replace(/\r$/, '')); if (row.some(Boolean)) records.push(row); row = []; cell = ''; }
    else cell += c;
  }
  if (cell || row.length) { row.push(cell.replace(/\r$/, '')); records.push(row); }
  const headers = records.shift();
  return records.map(r => Object.fromEntries(headers.map((h, i) => [h, r[i] ?? ''])));
}
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);
}
const norm = s => (s ?? '').normalize('NFC').replace(/\[(?:SFX|MUSIC|BGM|AMBIENCE|AMBIENT|SOUND|AUDIO|FX)\s*:[^\]]+\]/gi, '').replace(/\s+/g, ' ').trim();
const count = (items, key) => items.reduce((a, r) => { const k = r[key] ?? '(none)'; a[k] = (a[k] ?? 0) + 1; return a; }, {});
const dirs = fs.readdirSync(pack).filter(d => fs.statSync(path.join(pack, d)).isDirectory());
const packs = dirs.map(name => {
  const dir = path.join(pack, name), rows = csv(path.join(dir, 'manifest.csv'));
  const files = walk(dir).filter(f => f.toLowerCase().endsWith('.mp3'));
  return { name, rows, files, summary: {
    name, manifestRows: rows.length, mp3Files: files.length,
    bytes: files.reduce((n, f) => n + fs.statSync(f).size, 0),
    missingOrEmptyFiles: rows.filter(r => { const p = path.join(dir, r.relative_path ?? r.relativePath); return !fs.existsSync(p) || fs.statSync(p).size === 0; }),
  } };
});
const rowsFor = prefix => packs.find(p => p.name.startsWith(prefix)).rows;
const lessons = catalog.groups.flatMap(g => g.topics.flatMap(t => t.lessons.map(l => ({ ...l, age: `${g.startAge}-${g.endAge}`, topic: t.number, level: t.levelNumber }))));
const targets = lessons.flatMap(l => l.sentences);
const challenges = lessons.flatMap(l => l.challengeBank);
const missions = catalog.groups.flatMap(g => g.levels.flatMap(l => l.missionBank));
const sourceTargets = [...source.matchAll(/^(C\d+-L\d+-T\d+-B\d+-T\d+)\tEN=([^\r\n]*)\tVI=([^\r\n]*)/gm)].map(m => ({ id: m[1], english: m[2], vietnamese: m[3] }));
const targetMap = new Map(targets.map(t => [t.id, t]));
const sourceTargetMap = new Map(sourceTargets.map(t => [t.id, t]));
function sourceQuestions(kind) {
  const pattern = kind === 'challenge' ? /^C\d+-L\d+-T\d+-B\d+-Q\d+\t/ : /^C\d+-L\d+-M\d+\t/;
  const results = []; let current;
  for (const line of source.split(/\r?\n/)) {
    if (pattern.test(line)) { current = { id: line.split('\t')[0] }; results.push(current); }
    else if (line.trim() && !line.startsWith('  ')) current = undefined;
    else if (current) {
      const field = line.match(/^  (PROMPT_AUDIO|CHOICE_1_AUDIO|CHOICE_2_AUDIO|CORRECT_REFERENCE|TARGET_REF)=(.*)$/);
      if (field) current[field[1]] = field[2];
    }
  }
  return results;
}
function sourceQuestionDiffs(kind, appQuestions) {
  const byId = new Map(appQuestions.map(q => [q.id, q]));
  const sourceRows = sourceQuestions(kind);
  return { count: sourceRows.length, diffs: sourceRows.flatMap(r => {
    const q = byId.get(r.id);
    const fields = { prompt: r.PROMPT_AUDIO, choice1: r.CHOICE_1_AUDIO, choice2: r.CHOICE_2_AUDIO, answer: r.CORRECT_REFERENCE, target: r.TARGET_REF?.split(' ')[0] };
    const actual = { prompt: q?.prompt, choice1: q?.choices[0], choice2: q?.choices[1], answer: q?.correctAnswer, target: q?.targetId ?? q?.coverageTargetId };
    return Object.keys(fields).flatMap(k => norm(fields[k]) === norm(actual[k]) ? [] : [{ id:r.id, field:k, source:fields[k], app:actual[k] }]);
  }) };
}
const coreDiffs = rowsFor('05_').flatMap(r => {
  const target = targetMap.get(r.target_id), field = r.language === 'en' ? 'english' : 'vietnamese';
  if (!target || norm(target[field]) !== norm(r.text)) return [{ id: r.target_id, language: r.language, packText: r.text, appText: target?.[field] ?? null }];
  return [];
});
function questionDiffs(rows, questions, idKey) {
  const byId = new Map(questions.map(q => [q.id, q]));
  return rows.flatMap(r => {
    const q = byId.get(r[idKey]);
    const text = r.original_text ?? r.text;
    const appText = r.role === 'prompt' ? q?.prompt : q?.choices[Number(r.role.slice(-1)) - 1];
    const reasons = [];
    if (!q) reasons.push('missingId');
    if (norm(appText) !== norm(text)) reasons.push('text');
    if (norm(q?.correctAnswer) !== norm(r.correct_reference)) reasons.push('correctAnswer');
    if ((q?.targetId ?? q?.coverageTargetId) !== r.target_ref.split(' ')[0]) reasons.push('targetRef');
    return reasons.length ? [{ id: r[idKey], role: r.role, reasons, packText: text, appText, packAnswer: r.correct_reference, appAnswer: q?.correctAnswer, packTarget: r.target_ref.split(' ')[0], appTarget: q?.targetId ?? q?.coverageTargetId }] : [];
  });
}
const hookRows = rowsFor('03_');
const hookMatches = hookRows.map(r => ({ row: r, lesson: lessons.find(l => l.age === r.age && l.level === Number(r.level) && l.topic === Number(r.topic) && l.titleEn === r.lesson) }));
const repoAudio = walk('assets/audio').filter(f => /\.(mp3|wav|m4a|aac|ogg)$/i.test(f));
const repoBasenames = new Set(repoAudio.map(f => path.parse(f).name.toLowerCase()));
const report = {
  source: { coreTargets: sourceTargets.length, hookRows: source.split(/\r?\n/).filter(l => /^AGE=.*\tTYPE=/.test(l)).length },
  txtChallengeComparison: sourceQuestionDiffs('challenge', challenges),
  txtMissionComparison: sourceQuestionDiffs('mission', missions),
  app: { lessons: lessons.length, coreTargets: targets.length, challenges: challenges.length, missions: missions.length, roleplays: lessons.filter(l => l.rolePlay).length,
    audioProvider: catalog.audioProvider, manifestEntries: manifest.entries.length, manifestStatus: count(manifest.entries, 'qaStatus'), manifestKinds: count(manifest.entries, 'kind'),
    coreEnglishUrls: targets.filter(t => t.audioUrl).length, coreVietnameseUrls: targets.filter(t => t.vietnameseAudioUrl).length,
    coreIdsFoundInRepoAssets: targets.filter(t => repoBasenames.has(t.englishAudioId.toLowerCase()) || repoBasenames.has(t.vietnameseAudioId.toLowerCase())).length,
    introUrls: lessons.filter(l => l.introAudioUrl).length,
    songs: lessons.filter(l => l.songTitle).map(l => ({ code: l.code, title: l.songTitle, uri: l.songAudioUrl, fileExists: !!l.songAudioUrl && fs.existsSync(l.songAudioUrl.replace('asset:///', '')) })),
  },
  packs: packs.map(p => p.summary),
  core: { packTargets: new Set(rowsFor('05_').map(r => r.target_id)).size, audioTextDiffs: coreDiffs,
    appTargetsAbsentFromTxt: targets.filter(t => !sourceTargetMap.has(t.id)), txtTargetsAbsentFromApp: sourceTargets.filter(t => !targetMap.has(t.id)),
    txtAppTextDiffs: sourceTargets.filter(t => targetMap.has(t.id) && ['english', 'vietnamese'].some(k => norm(t[k]) !== norm(targetMap.get(t.id)[k]))),
  },
  challenges: { questions: new Set(rowsFor('06_').map(r => r.question_id)).size, diffs: questionDiffs(rowsFor('06_'), challenges, 'question_id') },
  missions: { questions: new Set(rowsFor('07_').map(r => r.mission_id)).size, diffs: questionDiffs(rowsFor('07_'), missions, 'mission_id') },
  hooks: { matched: hookMatches.filter(h => h.lesson).length,
    unmatched: hookMatches.filter(h => !h.lesson).map(h => h.row),
    missingInPack: lessons.filter(l => !hookMatches.some(h => h.lesson?.id === l.id)).map(l => ({code:l.code,title:l.titleEn,entry:l.entry})),
    textDiffs: hookMatches.filter(h => h.lesson && norm(h.row.originalAudio) !== norm(h.lesson.entry.text)).map(h => ({code:h.lesson.code,pack:h.row.originalAudio,app:h.lesson.entry.text})),
  },
  cues: { byId: count(rowsFor('01_'), 'cue_id'), kinds: count(rowsFor('01_'), 'kind'), missingLessonCueTemplates: csv(path.join(pack, dirs.find(d => d.startsWith('01_')), 'unresolved_dynamic_templates.csv')) },
  feedback: { byAge: count(rowsFor('02_'), 'age'), byState: count(rowsFor('02_'), 'state_code') },
  totalMp3Files: packs.reduce((n, p) => n + p.files.length, 0),
  totalMp3Bytes: packs.reduce((n, p) => n + p.summary.bytes, 0),
  starCountsAbovePackRange: lessons.map(l => ({ code: l.code, age: l.age, totalStars: l.sentences.length + (l.rolePlay?.turns.filter(t => t.speaker === 'child').length ?? 0) + 2 })).filter(l => l.totalStars > 9),
  roleplayLinesWithoutMatchingCoreText: lessons.filter(l => l.rolePlay).flatMap(l => l.rolePlay.turns.filter(t => !l.sentences.some(s => s.english === t.english)).map(t => ({ code:l.code, text:t.english }))),
};
fs.writeFileSync(path.join(root, 'outputs/audio-audit-2026-09-11/comparison.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ ...report, cues: { ...report.cues, missingLessonCueTemplates: report.cues.missingLessonCueTemplates.length } }, null, 2));
