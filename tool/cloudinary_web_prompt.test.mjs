import { readFile } from 'node:fs/promises';
import { createContext, runInContext } from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const html = await readFile(new URL('../web/index.html', import.meta.url), 'utf8');
const script = /<script>([\s\S]*?)<\/script>/.exec(html)[1];
function setup() {
  const audio = [];
  const speech = [];
  class FakeAudio {
    constructor(url) { this.url = url; audio.push(this); }
    play() { return Promise.resolve(); }
    pause() { this.paused = true; }
    removeAttribute() {}
    load() {}
  }
  const window = { setTimeout, clearTimeout, speechSynthesis: { cancel() {}, speak(value) { speech.push(value); } } };
  runInContext(script, createContext({ window, Audio: FakeAudio, SpeechSynthesisUtterance: class { constructor(text) { this.text = text; } } }));
  return { window, audio, speech };
}

test('recorded URL completes only when audio ends', async () => {
  const { window, audio, speech } = setup();
  const pending = window.innotrikVoicePromptSpeakAndWait('Xin chào', 'vi-VN', 'https://res.cloudinary.com/test/video/upload/hello.mp3');
  assert.equal(audio.length, 1);
  assert.equal(speech.length, 0);
  audio[0].onended();
  assert.equal(await pending, 'completed');
});

test('stop cancels audio and resolves the waiting caller', async () => {
  const { window, audio, speech } = setup();
  const pending = window.innotrikVoicePromptSpeakAndWait('Xin chào', 'vi-VN', 'https://res.cloudinary.com/test/video/upload/hello.mp3');
  const staleError = audio[0].onerror;
  window.innotrikVoicePromptStop();
  staleError();
  assert.equal(await pending, 'cancelled');
  assert.equal(audio[0].paused, true);
  assert.equal(speech.length, 0);
});

test('network errors fall back to the same text once', async () => {
  const { window, audio, speech } = setup();
  const pending = window.innotrikVoicePromptSpeakAndWait('Xin chào', 'vi-VN', 'https://res.cloudinary.com/test/video/upload/hello.mp3');
  const onerror = audio[0].onerror;
  onerror();
  onerror();
  assert.equal(speech.length, 1);
  assert.equal(speech[0].text, 'Xin chào');
  speech[0].onend();
  assert.equal(await pending, 'completed');
});
