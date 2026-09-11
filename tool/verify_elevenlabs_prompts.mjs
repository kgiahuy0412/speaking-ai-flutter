// Validate every generated MP3 against the plan, saved checksum and MPEG frames.
// Does not contact ElevenLabs or consume generation credits.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
const root = path.resolve(import.meta.dirname, '..');
const read = p => JSON.parse(fs.readFileSync(path.join(root,p),'utf8'));
const plan = read('outputs/elevenlabs-voice-pack/generation-plan.json');
const state = read('outputs/elevenlabs-voice-pack/generation-state.json');
const index = read('assets/data/elevenlabs_prompt_index.json');
const byId = new Map(index.clips.map(c=>[c.id,c]));
const failures = [], verified = [];

function mp3Info(data) {
  let offset = 0, frames = 0, samples = 0;
  if (data.toString('ascii',0,3) === 'ID3') {
    const size = ((data[6]&127)<<21)|((data[7]&127)<<14)|((data[8]&127)<<7)|(data[9]&127);
    offset = 10 + size + ((data[5]&16) ? 10 : 0);
  }
  while (offset + 4 <= data.length) {
    if (data.toString('ascii',offset,offset+3) === 'TAG' && offset+128 === data.length) {offset+=128;break;}
    const header = data.readUInt32BE(offset);
    if ((header>>>21) !== 0x7ff || ((header>>>19)&3)!==3 || ((header>>>17)&3)!==1) throw Error(`Invalid MPEG-1 Layer III frame at ${offset}`);
    const bitrate = [0,32,40,48,56,64,80,96,112,128,160,192,224,256,320][(header>>>12)&15];
    const rate = [44100,48000,32000][(header>>>10)&3];
    if (!bitrate || rate!==44100) throw Error('Unexpected bitrate or sample rate');
    const length = Math.floor(144000*bitrate/rate)+((header>>>9)&1);
    if (offset+length > data.length) throw Error('Truncated MPEG frame');
    offset+=length; frames++; samples+=1152;
  }
  if (offset!==data.length || frames<5) throw Error('Incomplete or empty MP3');
  return {frames, durationSeconds: Number((samples/44100).toFixed(3))};
}
for (const p of plan.clips) {
  try {
    const clip=byId.get(p.id), saved=state.clips[p.id];
    if (!clip || clip.text!==p.text || saved?.status!=='complete') throw Error('Missing or mismatched manifest/state entry');
    const bytes=fs.readFileSync(path.join(root,clip.asset));
    if(createHash('sha256').update(bytes).digest('hex')!==saved.sha256) throw Error('Checksum mismatch');
    verified.push({id:p.id,bytes:bytes.length,...mp3Info(bytes)});
  } catch(error) {failures.push({id:p.id,error:String(error)});}
}
if (index.clips.length!==plan.clips.length) failures.push({error:'Plan/manifest count mismatch'});
const report={voiceId:index.voiceId,modelId:index.modelId,planned:plan.clips.length,verified:verified.length,failed:failures.length,totalBytes:verified.reduce((n,c)=>n+c.bytes,0),reportedCharacterCost:Object.values(state.clips).reduce((n,c)=>n+Number(c.characterCost??0),0),maxDurationSeconds:Math.max(...verified.map(c=>c.durationSeconds)),totalDurationSeconds:verified.reduce((n,c)=>n+c.durationSeconds,0),failures,clips:verified};
fs.writeFileSync(path.join(root,'outputs/elevenlabs-voice-pack/audio-validation.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,clips:undefined},null,2));
if(failures.length)process.exitCode=1;
