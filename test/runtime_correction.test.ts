import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { QuranCorpus } from '@pinned/corpus';
import { QuranIndex, BASMALA, ISTIADHA } from '@pinned/search';
import { RecitationEngine } from '@pinned/engine';
import { StructuralRules, ayahOrderFlags, AYAH_ORDER_RULE_GUARDED } from '@pinned/structural';
import structuralIndex from '@pinned/structural-index';
import { CorrectionController } from '@pinned/controller';
import { correct, setExpected, stop, structuralOptions, WordEvidencePublisher } from '../tool/runtime/correction';

// Real pinned controller/bridge code with scripted acoustic evidence, not ASR.
const position = { surah: 112, ayah: 1, word: 3 };
const word = (n: number, overrides: Record<string, unknown> = {}) => ({
  surah: 112, ayah: 1, word: n, wordIndex: n, state: 'ok',
  distance: 0, heardRatio: 1, margin: 1, vowelErrors: 0, vowelMargin: 0,
  ...overrides,
});
const evidence = (overrides: Record<string, unknown>) =>
  [word(0), word(1, overrides), word(2), word(3)] as any;

test('pinned omission rule needs anchored, persistent evidence', () => {
  const controller = new CorrectionController();
  controller.setMode('correction');
  const words = evidence({ state: 'skipped', distance: 1, heardRatio: 0 });
  assert.equal(controller.observe(words, position, 100), false);
  assert.equal(controller.observe(words, position, 112), true);
  assert.equal(controller.state.phase, 'error');
  assert.equal(controller.state.issue?.kind, 'possible_omission');
  assert.equal(controller.state.issue?.word, 1);
});

test('silence and weak/uncertain context do not establish a spoken error', () => {
  const controller = new CorrectionController();
  controller.setMode('correction');
  assert.equal(controller.observe([], position, 0), false);
  assert.equal(controller.observe([], position, 20), false);
  const words = evidence({ state: 'wrong', distance: 1, heardRatio: 1 });
  words[0].margin = 0.1;
  words[2].margin = 0.1;
  assert.equal(controller.observe(words, position, 40), false);
  assert.equal(controller.observe(words, position, 60), false);
  assert.equal(controller.state.phase, 'idle');
});

test('retry rejects an old attempt and needs a fresh clear prefix', () => {
  const controller = new CorrectionController();
  controller.setMode('correction');
  const wrong = evidence({ state: 'wrong', distance: 1 });
  controller.observe(wrong, position, 100);
  controller.observe(wrong, position, 112);
  assert.equal(controller.act('retry'), true);
  assert.equal(controller.state.attempt, 1);
  const clear = evidence({});
  assert.equal(controller.observe(clear, position, 0, 0), false);
  assert.equal(controller.observe(wrong, position, 0, 1), false);
  assert.equal(controller.observe(clear, position, 4, 1), false);
  assert.equal(controller.observe(clear, position, 16, 1), true);
  assert.equal(controller.state.phase, 'corrected');
  assert.equal(controller.act('continue'), true);
  assert.equal(controller.state.phase, 'idle');
  assert.equal(controller.state.outcome, 'corrected');
});

test('default upstream repetition is a note, not an interrupt', () => {
  const controller = new CorrectionController();
  controller.setMode('correction');
  const words = evidence({ gop: 0, repGain: 6 });
  controller.observe(words, position, 0);
  assert.equal(controller.observe(words, position, 12), false);
  assert.equal(controller.state.phase, 'idle');
  assert.deepEqual(controller.takeNotes().map(n => n.kind), ['possible_repetition']);
  assert.deepEqual(controller.takeNotes(), []);
});

test('bridge expected passage validates corpus endpoints and supports clear', () => {
  let expected: unknown;
  const session = { wordCount: (s: number, a: number) => s === 112 && a >= 1 && a <= 4 ? 4 : 0,
    setExpected: (value: unknown) => { expected = value; } } as any;
  setExpected(session, { surah: 112, ayah: 1, ayahEnd: 4 });
  assert.deepEqual(expected, { surah: 112, ayah: 1, ayahEnd: 4 });
  assert.throws(() => setExpected(session, { surah: 112, ayah: 1, ayahEnd: 5 }));
  setExpected(session, null);
  assert.equal(expected, null);
});

test('bridge terminal Stop closes an open issue before flushing', async () => {
  for (const phase of ['error', 'retrying', 'corrected', 'idle']) {
    const calls: string[] = [];
    const session = { correction: { state: { phase, attempt: 0 } },
      correct: (action: string) => { calls.push(action); session.correction.state.phase = 'idle'; session.correction.state.attempt++; },
      stop: async () => { calls.push('stop'); } } as any;
    await stop(session);
    assert.deepEqual(calls, phase === 'idle' ? ['stop'] : ['close', 'stop']);
  }
});

test('structural options are explicit and preserve guarded upstream rules', () => {
  assert.equal(structuralOptions('off'), false);
  assert.deepEqual(structuralOptions('onStop'), {ayahOrder:'guarded',similarVerse:true,timing:'stop'});
  assert.deepEqual(structuralOptions('onPause'), {ayahOrder:'guarded',similarVerse:true,timing:'pause'});
});

test('Stop publishes every queued structural finding, not just the first', async () => {
  const calls: string[] = [];
  let remaining = 3;
  const session = { correction: {state:{phase:'idle',attempt:0}},
    stop: async () => { calls.push('flush'); session.correction.state.phase='error'; },
    correct: () => { calls.push('close'); remaining--; session.correction.state.attempt++;
      session.correction.state.phase=remaining ? 'error' : 'idle'; } } as any;
  await stop(session,()=>calls.push('evidence'));
  assert.deepEqual(calls,['flush','evidence','close','close','close']);
});

test('word evidence is replacement/revision scoped and does not publish nonfinite optional scores', () => {
  const output: any[] = [];
  const publisher = new WordEvidencePublisher(true, event=>output.push(event));
  let words = [word(0,{gop:-Infinity})];
  const session = { verdicts:()=>words, transcript:'abc', correction:{state:{attempt:0}} } as any;
  publisher.publish(session); publisher.publish(session);
  assert.equal(output.length,1);
  assert.equal(output[0].words[0].gop,undefined);
  words=[]; publisher.publish(session);
  assert.deepEqual(output[1].words,[]);
  assert.equal(output[1].revision,2);
  publisher.reset(); publisher.publish(session);
  assert.equal(output[2].revision,1);
});

test('bridge rejects actions outside their phase instead of silently ignoring', () => {
  const session = { correction: { state: { phase: 'idle' } }, correct: () => { throw Error('not called'); } } as any;
  assert.throws(() => correct(session, 'retry'), /not valid/);
  assert.throws(() => correct(session, 'typo'), /not valid/);
});

test('pinned engine evidence for clean vs next-ayah start; structural leading-gap limitation', {
  skip: !process.env.TILAWA_TEST_CORPUS,
}, () => {
  const bytes = readFileSync(process.env.TILAWA_TEST_CORPUS!);
  assert.equal(createHash('sha256').update(bytes).digest('hex'),
    '24360c05ec88fcacf3419c1fe6cd81d69e653326a0bf0e4fb507e7b98fc88127');
  const corpus = new QuranCorpus(JSON.parse(bytes.toString()));
  const index = new QuranIndex(corpus);
  const rules = new StructuralRules(corpus, structuralIndex as any);
  const expected = {surah:112,ayah:1,ayahEnd:4};
  const run = (start:number) => {
    const engine = new RecitationEngine(corpus,index);
    engine.setCorrection(true); engine.startSearch(); engine.setExpected(expected);
    let frame=0;
    const tokens: any[]=[];
    const snapshots: any[]=[];
    const publications:any[]=[];
    const publisher=new WordEvidencePublisher(true,e=>publications.push(e),JSON.parse(bytes.toString()));
    publisher.setExpected(expected);
    const publish=()=>publisher.publish({verdicts:()=>engine.tracer?.verdicts(false)??[],
      transcript:tokens.map(t=>t.sym).join(''),correction:{state:{attempt:0}}} as any);
    for (let ayah=start;ayah<=4;ayah++) {
      for (const sym of corpus.ayahPhonemes(112,ayah)) {
        const token={sym,frame:++frame,margin:1}; tokens.push({...token,t:frame*.04});
        engine.feed([token],frame);
        snapshots.push(engine.tracer?.verdicts(false) ?? []);
        publish();
      }
      frame+=20; engine.feed([],frame);
    }
    return {snapshots,tokens,publications};
  };
  const clean=run(1), skipped=run(2);
  if(process.env.TILAWA_START_EVIDENCE) writeFileSync(process.env.TILAWA_START_EVIDENCE,
    JSON.stringify({clean:clean.publications,skipped:skipped.publications}));
  const clear = (v:any) => v.state==='ok' && v.distance<=.15 && v.margin>=.55 && v.heardRatio>=.75 && v.heardRatio<=1.3;
  assert.ok(clean.snapshots.some(vs=>vs.some((v:any)=>v.ayah===1 && v.word===0 && clear(v))));
  const advancing=skipped.snapshots.filter(vs=>vs.filter((v:any)=>v.ayah===2 && clear(v)).length>=2);
  assert.ok(advancing.length>1,'next-ayah audio must produce actual next-ayah verdict evidence');
  const flags=ayahOrderFlags(rules.ayahOrderCandidate(skipped.tokens,rules.ayahOrderWindow(expected,null)),AYAH_ORDER_RULE_GUARDED);
  assert.equal(flags.some(f=>f.ayah===1),false,'leading omissions have no flanking segment');
  const prefixOutput:any[]=[];
  const publisher=new WordEvidencePublisher(true,e=>prefixOutput.push(e),JSON.parse(bytes.toString()));
  publisher.setExpected(expected);
  publisher.publish({verdicts:()=>advancing[0],transcript:skipped.tokens.map(t=>t.sym).join(''),
    correction:{state:{attempt:0}}} as any);
  const prefix=prefixOutput[0].start_comparison;
  console.log('PREFIX_COMPARISON',JSON.stringify(prefix));
  assert.equal(prefix.ayah,2);
  assert.ok(prefix.expected_distance>=.45 && prefix.later_distance<=.2);
  for (const preamble of ['', BASMALA, ISTIADHA+BASMALA]) {
    const cleanOutput:any[]=[];
    const cleanPublisher=new WordEvidencePublisher(true,e=>cleanOutput.push(e),JSON.parse(bytes.toString()));
    cleanPublisher.setExpected(expected);
    cleanPublisher.publish({verdicts:()=>[],
      transcript:preamble+clean.tokens.map(t=>t.sym).join(''),correction:{state:{attempt:0}}} as any);
    assert.equal(cleanOutput[0].start_comparison.expected_distance,0,'clean preamble must not create skipped start evidence');
  }
  console.log('PINNED_SYNTHETIC_START', JSON.stringify({
    clearOpening: true, nextAyahEvidence: advancing.length, leadingStructuralFlags: flags,
    sample: advancing[0].map((v:any)=>({ayah:v.ayah,word:v.word,state:v.state,ratio:v.heardRatio})),
  }));
});
