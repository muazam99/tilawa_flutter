// Native inference adapter; matching/tracking stay pinned upstream.
import { createZipformerSession } from '@pinned/session';
import { correct, setExpected, stop, structuralOptions, WordEvidencePublisher } from './correction';
let session: any;
let evidence: WordEvidencePublisher;
let samples = 0, sequence: any = null, score: number | null = null, next = 0;
const pending = new Map<number, {resolve: (x: any)=>void; reject:(x:any)=>void}>();
const post = (value: unknown) => (globalThis as any).sendMessage('nativeProbe', JSON.stringify(value));
(globalThis as any).nativeDeliver = (id: number, value: any, error: string | null) => {
  const p = pending.get(id); if (!p) return; pending.delete(id);
  if (error) p.reject(new Error(error)); else p.resolve(value);
};
const infer = (x: any) => new Promise<any>((resolve,reject) => {
  const id = ++next; pending.set(id,{resolve,reject});
  post({kind:'infer',id,x:Array.from(x.data),dims:x.dims,reset:x.reset === true});
});
class Tensor {
  constructor(public type: string, public data: any, public dims: number[]) {}
}
const snapshot = () => ({samples,state:session.engineState,transcript:session.transcript,sequence,score,correction:session.correction.state});
(globalThis as any).nativeOperation = async (method: string, data: any) => {
  switch(method) {
    case 'initialize':
      session = await createZipformerSession({
        session: {async run(feeds: any) {
          // Runner resets also happen internally on silence/relocation and on
          // correction actions. Keep native recurrent tensors in the same epoch.
          const result = await infer({ ...feeds.x, reset: feeds.processed_lens.data[0] === 0n });
          const out: any = {log_probs: new Tensor('float32',Float32Array.from(result.logProbs),result.logDims)};
          for (const state of result.states) {
            out['new_'+state.name] = new Tensor(state.type,
              state.name === 'processed_lens' ? BigInt64Array.from([BigInt(state.processedLens)]) : new Float32Array(0), state.dims);
          }
          return out;
        }}, Tensor, corpus:data.corpus,io:data.io, structural:structuralOptions(data.structuralCorrection),slipHead:false,
        minWordFraction:data.minWordFraction, enableFallback:data.enableFallback,
        fallbackMaxDistance:data.fallbackMaxDistance,stayOnSurah:data.stayOnSurah,
        tailSeconds:data.tailSeconds,debug:data.debug,
        onEvent(event: any) {
          if(event.type==='final_sequence'){sequence=event.verses;score=event.confidence;}
          post({kind:'event',event});
        },
      });
      session.setMode(data.mode === 'correction' ? 'correction' : 'tracking');
      setExpected(session, data.expectedPassage);
      evidence = new WordEvidencePublisher(data.wordEvidence === true,
        event => post({kind:'event',event}), data.corpus);
      evidence.setExpected(data.expectedPassage);
      samples=0;sequence=null;score=null;return snapshot();
    case 'feed':
      if (session.correction.state.phase === 'error' || session.correction.state.phase === 'corrected') {
        post({kind:'event',event:{type:'audio_discarded',samples:data.pcm.length,reason:'correction_awaiting_action'}});
      } else await session.feed(Float32Array.from(data.pcm));
      samples+=data.pcm.length;evidence.publish(session);return snapshot();
    case 'stop': evidence.publish(session);await stop(session,()=>evidence.publish(session,true));return snapshot();
    case 'reset': session.reset();evidence.reset();samples=0;sequence=null;score=null;return snapshot();
    case 'setExpected': setExpected(session, data.passage);evidence.setExpected(data.passage);return snapshot();
    case 'correct': correct(session, data.action);evidence.publish(session);return snapshot();
    case 'wordCount': {
      const {surah,ayah} = data;
      if (!Number.isInteger(surah) || !Number.isInteger(ayah) || surah < 1 || surah > 114 || ayah < 1) return {words:0};
      const words = session.wordCount(surah,ayah);
      return {words:Number.isInteger(words) && words > 0 ? words : 0};
    }
    case 'dispose': session=null;sequence=null;score=null;return {disposed:true};
    default: throw Error('Unknown method '+method);
  }
};
