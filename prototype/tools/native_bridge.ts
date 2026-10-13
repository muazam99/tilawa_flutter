// Private native-inference experiment; matching/tracking stay pinned upstream.
import { createZipformerSession } from '@pinned/session';
let session: any;
let samples = 0, sequence: any = null, score: number | null = null, next = 0;
const pending = new Map<number, {resolve: (x: any)=>void; reject:(x:any)=>void}>();
const post = (value: unknown) => (globalThis as any).sendMessage('nativeProbe', JSON.stringify(value));
(globalThis as any).nativeDeliver = (id: number, value: any, error: string | null) => {
  const p = pending.get(id); if (!p) return; pending.delete(id);
  if (error) p.reject(new Error(error)); else p.resolve(value);
};
const infer = (x: any) => new Promise<any>((resolve,reject) => {
  const id = ++next; pending.set(id,{resolve,reject});
  post({kind:'infer',id,x:Array.from(x.data),dims:x.dims});
});
class Tensor {
  constructor(public type: string, public data: any, public dims: number[]) {}
}
const snapshot = () => ({samples,state:session.engineState,transcript:session.transcript,sequence,score});
(globalThis as any).nativeOperation = async (method: string, data: any) => {
  switch(method) {
    case 'initialize':
      session = await createZipformerSession({
        session: {async run(feeds: any) {
          const result = await infer(feeds.x);
          const out: any = {log_probs: new Tensor('float32',Float32Array.from(result.logProbs),result.logDims)};
          for (const state of result.states) {
            out['new_'+state.name] = new Tensor(state.type,
              state.name === 'processed_lens' ? BigInt64Array.from([BigInt(state.processedLens)]) : new Float32Array(0), state.dims);
          }
          return out;
        }}, Tensor, corpus:data.corpus,io:data.io, structural:false,slipHead:false,
        minWordFraction:data.minWordFraction, enableFallback:data.enableFallback,
        fallbackMaxDistance:data.fallbackMaxDistance,stayOnSurah:data.stayOnSurah,
        tailSeconds:data.tailSeconds,debug:data.debug,
        onEvent(event: any) {
          if(event.type==='final_sequence'){sequence=event.verses;score=event.confidence;}
          post({kind:'event',event});
        },
      });
      session.setMode('tracking'); samples=0;sequence=null;score=null;return snapshot();
    case 'feed': await session.feed(Float32Array.from(data.pcm)); samples+=data.pcm.length;return snapshot();
    case 'stop': await session.stop();return snapshot();
    case 'reset': session.reset();samples=0;sequence=null;score=null;return snapshot();
    case 'wordCount': return {words:session.wordCount(data.surah,data.ayah)};
    case 'dispose': session=null;sequence=null;score=null;return {disposed:true};
    default: throw Error('Unknown method '+method);
  }
};
