// Build a reviewable, deduplicated Vietnamese pack from the Dart AST audit and
// shipped curriculum. Existing recordings are reused; no network or API key.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

const root = path.resolve(import.meta.dirname, '..');
const read = p => JSON.parse(fs.readFileSync(path.join(root, p), 'utf8'));
const output = path.join(root, 'outputs/elevenlabs-voice-pack');
const audit = read('outputs/elevenlabs-voice-pack/source-audit.json');
const old = read('assets/data/homi_audio_index.json');
const curriculum = read('assets/data/listening_lessons.json');
const fallback = read('assets/data/homi_ai_fallback_catalog_v1.json');
const norm = s => s.trim().replace(/\s+/g, ' ');
const texts = new Map(), reused = new Map(), unresolved = [];
const existing = new Map(old.clips.filter(c => c.locale === 'vi-VN' && (c.kind === 'system' || c.kind === 'core')).map(c => [norm(c.text), c]));
const knownSequences = new Set(old.sequences.map(s => norm(s.text)));
const topics = curriculum.groups.flatMap(g => g.topics);
const lessons = topics.flatMap(t => t.lessons);
const unique = values => [...new Set(values)];
const numbers = (min, max) => Array.from({length: max - min + 1}, (_, i) => min + i);
const maxStars = Math.max(...lessons.map(l => l.sentences.length + (l.rolePlay?.turns.filter(t => t.speaker === 'child').length ?? 0) + 2));
const mainOpening = 'HOMI đây. Bạn muốn dịch sang tiếng Anh, học theo chủ đề hay học bộ từ vựng?';

function add(text, source, audioId) {
  text = norm(text);
  if (!text || /\[(?:DYNAMIC|SONG_TITLE|SFX|MUSIC|BGM)/.test(text)) return;
  const identified = audioId && old.clips.find(c => c.id === audioId && c.locale === 'vi-VN' && norm(c.text) === text);
  if (identified) { reused.set(text, identified); return; }
  const clip = existing.get(text);
  if (clip) { reused.set(text, clip); return; }
  if (knownSequences.has(text)) return;
  const id = text === mainOpening ? 'main_opening' : 'vi_' + createHash('sha256').update('vi-VN:' + text).digest('hex').slice(0, 20);
  const entry = texts.get(text) ?? {id, text, audioIds: [], sources: []};
  if (audioId && !entry.audioIds.includes(audioId)) entry.audioIds.push(audioId);
  if (!entry.sources.includes(source)) entry.sources.push(source);
  texts.set(text, entry);
}

// Reviewed speech-producing members. UI labels, error/debug messages and ASR
// recognition phrases are excluded from paid generation.
function include(r) {
  const file = path.basename(r.file), m = r.member;
  if (file === 'main_voice_assistant_flow.dart') return m !== 'completedText';
  if (file === 'vocabulary_flow_v3.dart' || file === 'lesson_guide_flow.dart') return true;
  if (file === 'v4_completion_flow.dart') return m === 'v4CompletionPrompt';
  if (file === 'conversation_controller.dart') return m === '_unclearSpeechMessage';
  if (file === 'active_learning_module.dart') return m === 'execute';
  if (file === 'lesson_intro_screen.dart') return ['_prepareGuideText', 'topicLead', 'lessonLead', 'handleMainCommand'].includes(m);
  if (file === 'lesson_practice_screen.dart') return ['handleMainCommand', '_awardLessonStar', '_announceV4ActivityMilestone', '_showV4CompletionChoice', '_runV4LevelMissionIfNeeded', 'prompt'].includes(m) || (m === 'message' && r.line < 2600);
  if (file === 'lesson_challenge_screen.dart') return ['handleMainCommand', '_playCurrentPrompt', '_advance'].includes(m);
  if (file === 'lesson_mission_screen.dart') return ['handleMainCommand', '_playCurrentPrompt', '_speakReinforcementTarget'].includes(m);
  if (file === 'lesson_review_screen.dart') return ['handleMainCommand', 'prompt'].includes(m);
  if (file === 'song_karaoke_screen.dart') return m === 'handleMainCommand';
  if (file === 'topic_lesson_list_screen.dart') return m === 'message';
  if (file === 'topic_listening_screen.dart') return ['lead', '_startLevelTopicSelection', 'message'].includes(m) || (m === '_openTopic' && !r.text);
  if (file === 'vocabulary_practice_screen.dart') return ['_startCurrent', 'handleMainCommand'].includes(m);
  return false;
}

function values(expr, row) {
  if (/^(lessonTitleEn|lesson.titleEn)$/.test(expr)) {
    const applicable = /lesson_guide_flow/.test(row.file) && ['entry','ending'].includes(row.member)
      ? lessons.filter(l => !l.entry || !l.challengeBank?.length)
      : lessons;
    return unique(applicable.map(l => l.titleEn));
  }
  if (expr === 'topic.titleEn') return unique(topics.map(t => t.titleEn));
  if (/^(level.number|levelNumber|nextLevel \?\? ''|_topicSelectionLevelNumber \?\? 1|current)$/.test(expr)) return [1, 2, 3];
  if (/^(topicNumber(?: \?\? '')?|topicContent.number|content.number)$/.test(expr)) return unique(topics.map(t => t.number));
  if (/topics.length/.test(expr) && !/topicNumbers/.test(expr)) return unique(curriculum.groups.map(g => g.topics.length));
  if (/topicNumbers.length/.test(expr)) return [3, 4];
  if (/lessons.length/.test(expr)) return unique(topics.map(t => t.lessons.length));
  if (/^(lessonNumber|replayLesson|nextLesson|previous.number)$/.test(expr)) return numbers(1, Math.max(...topics.map(t => t.lessons.length)));
  if (expr === 'minimumAge') return [Math.min(...curriculum.groups.map(g => g.startAge))];
  if (expr === 'maximumAge') return [Math.max(...curriculum.groups.map(g => g.endAge))];
  if (/^(remainingStars|_newStarsThisLesson|_newRolePlayStars)$/.test(expr)) return numbers(1, maxStars);
  if (expr === 'total' && /vocabulary_flow/.test(row.file)) return null; // User-owned star count is unbounded.
  return null;
}

const selected = audit.filter(include);
for (const r of selected) {
  const source = `${r.file}:${r.line}`;
  if (r.text != null) {
    if (r.text.includes('[SONG_TITLE]')) {
      for (const title of unique(lessons.map(l => l.songTitle).filter(Boolean))) add(r.text.replaceAll('[SONG_TITLE]', title), source);
    } else add(r.text, source);
    continue;
  }
  // Context-dependent compositions are expanded below from real catalog rows.
  if (['continuousTranslationPrompt', 'beginLevelTopicSelection', '_startLevelTopicSelection', '_lessonSelectionPrompt', 'lessonLead', 'topicLead'].includes(r.member) || r.parts.some(p => ['topicLead', 'levelLead', 'lead'].includes(p.expression))) continue;
  const expressions = unique(r.parts.map(p => p.expression).filter(Boolean));
  const choices = expressions.map(e => values(e, r));
  if (choices.some(v => v === null)) { unresolved.push(r); continue; }
  let combinations = [{}];
  for (let i = 0; i < expressions.length; i++) combinations = combinations.flatMap(c => choices[i].map(v => ({...c, [expressions[i]]: v})));
  for (const c of combinations) add(r.parts.map(p => p.text ?? c[p.expression]).join(''), source);
}

for (const item of [...fallback.assistantPrompts, ...fallback.silenceScenarios]) if (item.message?.kind === 'literal') add(item.message.raw, `homi_ai_fallback_catalog_v1:${item.id}`);
for (const item of fallback.fallbackPolicies) for (const field of ['firstPrompt', 'secondPrompt']) if (item[field]?.kind === 'literal') add(item[field].raw, `homi_ai_fallback_catalog_v1:${item.id}:${field}`);
const promptById = Object.fromEntries(fallback.assistantPrompts.map(p => [p.id, p.message.raw]));
add(`${promptById['AI-020']} ${promptById['AI-022']}`, 'MainVoiceAssistantFlow.continuousTranslationPrompt');
for (const sequence of old.sequences) for (const part of sequence.parts) {
  if ((part.locale ?? 'vi-VN') !== 'vi-VN') continue;
  const clip = old.clips.find(c => c.id === part.audioId);
  if (!clip) add(part.text, 'homi_audio_index:sequence', part.audioId);
}
for (const missing of old.missing) if (!missing.id.endsWith('_EN')) add(missing.text, 'homi_audio_index:missing', missing.id);
// These strings arrive indirectly from JSON, so a Dart string-literal audit
// alone cannot find them. Preserve contextual recordings by their explicit ID.
for (const lesson of lessons) {
  if (lesson.rolePlay?.scenarioVi) add(lesson.rolePlay.scenarioVi, `curriculum:${lesson.code}:rolePlay.scenarioVi`);
  if (lesson.entry?.text) add(lesson.entry.text, `curriculum:${lesson.code}:entry`, `${lesson.code}_ENTRY`);
  for (const sentence of lesson.sentences) add(sentence.vietnamese, `curriculum:${sentence.id}:vietnamese`, sentence.vietnameseAudioId);
  for (const challenge of lesson.challengeBank ?? []) {
    add(challenge.prompt, `curriculum:${challenge.id}:prompt`, `${challenge.id}_PROMPT`);
    if (challenge.correctVietnamese) add(challenge.correctVietnamese, `curriculum:${challenge.id}:correctVietnamese`);
  }
}
for (const group of curriculum.groups) for (const level of group.levels) for (const mission of level.missionBank) {
  add(mission.prompt, `curriculum:${mission.id}:prompt`, `${mission.id}_PROMPT`);
  if (mission.correctVietnamese) add(mission.correctVietnamese, `curriculum:${mission.id}:correctVietnamese`);
}
for (const topic of topics) {
  const total = topic.lessons.length;
  add(`Có ${total} bài học. Con muốn học bài số mấy`, 'MainVoiceAssistantFlow._openTopic');
  add(`Chủ đề ${topic.titleVi} có ${total} bài học. Con muốn học bài số mấy?`, 'MainVoiceAssistantFlow._lessonSelectionPrompt');
  add(`Chủ đề ${topic.titleVi} có ${total} bài học. Con đã học xong cả ${total} bài. Con muốn học lại bài số mấy?`, 'MainVoiceAssistantFlow._lessonSelectionPrompt');
  for (let mask = 1; mask < (1 << total) - 1; mask++) {
    const completed = numbers(1,total).filter(n => mask & (1 << (n - 1)));
    const next = numbers(1,total).find(n => !completed.includes(n));
    add(`Chủ đề ${topic.titleVi} có ${total} bài học. Con đã học xong bài ${completed.join(' và bài ')}. Con muốn tiếp tục bài ${next} hay học lại bài nào?`, 'MainVoiceAssistantFlow._lessonSelectionPrompt');
  }
}
// Complete bilingual curriculum targets already have recordings, except those
// explicitly listed as missing above. Parent-created/dynamic vocabulary keeps
// device TTS because its text is not known at build time.
add(mainOpening, 'MainVoiceAssistantFlow.openingPrompt');
const clips = [...texts.values()].sort((a,b) => a.id === 'main_opening' ? -1 : b.id === 'main_opening' ? 1 : a.id.localeCompare(b.id));
const report = {scope: 'Vietnamese device-TTS prompts; preserve existing lesson audio', auditedExpressions: audit.length, selectedExpressions: selected.length, plannedClips: clips.length, characters: clips.reduce((n,c) => n + [...c.text].length, 0), reusedExistingClips: reused.size, unresolvedTemplates: unresolved, dynamicFallbacks: ['User-authored vocabulary/translations', 'Unbounded user star totals'], reused: [...reused.values()].map(c => ({text:c.text, asset:c.asset}))};
fs.writeFileSync(path.join(output,'generation-plan.json'), JSON.stringify({schemaVersion:1, clips},null,2)+'\n');
fs.writeFileSync(path.join(output,'audit-report.json'), JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report, reused:undefined, unresolvedTemplates: unresolved.map(r => `${r.file}:${r.line} ${r.expression}`)},null,2));
