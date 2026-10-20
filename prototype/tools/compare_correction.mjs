// Private, offline real-audio replay. No microphone, uploads or model changes.
// node prototype/tools/compare_correction.mjs <assets-dir> <mono16k-pcm16.wav> <new-output-dir>
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { build } from '../node_modules/esbuild/lib/main.js';
import * as ort from '../node_modules/onnxruntime-web/dist/ort.wasm.min.mjs';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const [assetsArg,clipArg,outArg]=process.argv.slice(2);
if(!assetsArg||!clipArg||!outArg) throw Error('Required: assets directory, mono16k PCM16 WAV, NEW output directory.');
const assets=resolve(assetsArg), clip=resolve(clipArg), output=resolve(outArg);
const hash=data=>createHash('sha256').update(data).digest('hex');
const baseline=JSON.parse(await readFile(join(root,'prototype/baseline.json'),'utf8'));
const pinned=join(root,'prototype/.cache/upstream/packages/core/src/recitation');
const runtimeManifest=JSON.parse(await readFile(join(root,'assets/runtime/manifest.json'),'utf8'));
const nativeBytes=await readFile(join(root,'assets/runtime/native.js'));
const artifact=runtimeManifest.artifacts.find(a=>a.name==='native.js');
if(hash(nativeBytes)!==artifact.sha256 || nativeBytes.length!==artifact.bytes) throw Error('Native runtime integrity mismatch');
const input=await readFile(clip);
if(input.toString('ascii',0,4)!=='RIFF'||input.toString('ascii',8,12)!=='WAVE') throw Error('Use WAV (PCM16 mono16k), convert compressed recordings first.');
let format, audio;
for(let offset=12;offset+8<=input.length;) {
  const name=input.toString('ascii',offset,offset+4), size=input.readUInt32LE(offset+4), start=offset+8;
  if(start+size>input.length)throw Error('Truncated WAV');
  if(name==='fmt ') format={encoding:input.readUInt16LE(start),channels:input.readUInt16LE(start+2),rate:input.readUInt32LE(start+4),bits:input.readUInt16LE(start+14)};
  if(name==='data')audio=input.subarray(start,start+size);
  offset=start+size+(size%2);
}
if(!format||format.encoding!==1||format.channels!==1||format.rate!==16000||format.bits!==16||!audio||audio.length%2)throw Error('Requires mono16k PCM16 WAV; no guessed rates or hidden resampling.');
if(audio.length>16000*2*120)throw Error('Keep comparison clips under two minutes.');
const pcm=Float32Array.from({length:audio.length/2},(_,i)=>audio.readInt16LE(i*2)/32768);
const corpusBytes=await readFile(join(assets,'corpus.json'));
const ioBytes=await readFile(join(assets,'io.json'));
const model=await readFile(join(assets,'model.onnx'));
if(hash(corpusBytes)!=='24360c05ec88fcacf3419c1fe6cd81d69e653326a0bf0e4fb507e7b98fc88127' ||
   hash(model)!=='bfb5b712695634a6099b45a6a78003bd5103417c4eae6338277d54679254905a' ||
   hash(ioBytes)!=='7dca1dafd6ee26044a0d3ba6b9483278203f55df7cc95d40cda865183a0d797e')throw Error('Pinned recognition asset hash mismatch');
const corpus=JSON.parse(corpusBytes), io=JSON.parse(ioBytes);
// Check cached source identities against the previously verified immutable tree.
// Runtime generator must be run before this tool when restoring/changing cache.
const compiled=await build({stdin:{contents:`export {createZipformerSession} from ${JSON.stringify(join(pinned,'session.ts'))};`,resolveDir:root},
  bundle:true,write:false,platform:'node',format:'cjs',target:'node22'});
const module={exports:{}};
new Function('require','module','exports',new TextDecoder().decode(compiled.outputFiles[0].contents))(
  createRequire(import.meta.url),module,module.exports);
ort.env.wasm.numThreads=1;
ort.env.wasm.wasmPaths=pathToFileURL(join(root,'prototype/node_modules/onnxruntime-web/dist/')).href;
const settings={mode:'correction',expectedPassage:null,structuralCorrection:'onStop',wordEvidence:true,
  minWordFraction:.5,enableFallback:false,fallbackMaxDistance:.5,stayOnSurah:false,tailSeconds:2,debug:false};
async function modelSession(){return ort.InferenceSession.create(model,{executionProviders:['wasm'],graphOptimizationLevel:'all'});}
async function original(){
  const engine=await modelSession(), events=[], evidence=[];
  const session=await module.exports.createZipformerSession({session:engine,Tensor:ort.Tensor,corpus,io,
    structural:{ayahOrder:'guarded',similarVerse:true,timing:'stop'},slipHead:false,
    enableFallback:false,onEvent:event=>events.push(event)});
  session.setMode('correction');
  let at=0;
  const resume=()=>{while(session.correction.state.phase!=='idle')session.correct('dismiss');};
  try {
    for(;at<pcm.length;at+=7680){
      await session.feed(pcm.subarray(at,Math.min(pcm.length,at+7680)));
      evidence.push({samples:Math.min(pcm.length,at+7680),words:session.verdicts()});
      resume(); // Explicit diagnostic policy: log issue then dismiss, never call it corrected.
    }
    await session.stop();
    while(session.correction.state.phase!=='idle')session.correct('close');
    return {events,evidence};
  } finally {await engine.release();}
}
async function packaged(){
  const engine=await modelSession(),events=[],evidence=[];
  let states={}, samples=0, context;
  const reset=()=>{
    for(const tensor of Object.values(states))tensor.dispose();
    states=Object.fromEntries(io.inputs.filter(i=>i.name!=='x').map(i=>[i.name,new ort.Tensor(i.dtype,
      i.dtype==='int64'?new BigInt64Array(i.dims.reduce((a,b)=>a*b,1)):new Float32Array(i.dims.reduce((a,b)=>a*b,1)),i.dims)]));
  };
  reset();
  let inference=Promise.resolve();
  context=vm.createContext({console,sendMessage:(channel,message)=>{
    const data=typeof message==='string'?JSON.parse(message):message;
    if(data.kind==='event') {
      if(data.event.type==='word_evidence')evidence.push({samples,words:data.event.words});
      else events.push(data.event);
    }
    if(data.kind==='infer')inference=inference.then(async()=>{
      let outputs,x;
      try{
        if(data.reset)reset();
        x=new ort.Tensor('float32',Float32Array.from(data.x),data.dims);
        outputs=await engine.run({x,...states});
        const descriptions=io.inputs.filter(i=>i.name!=='x').map(i=>({name:i.name,type:i.dtype,
          dims:outputs['new_'+i.name].dims,...i.name==='processed_lens'?{processedLens:String(outputs['new_'+i.name].data[0])}:{}}));
        const result={logProbs:Array.from(outputs.log_probs.data),logDims:outputs.log_probs.dims,states:descriptions};
        for(const tensor of Object.values(states))tensor.dispose();
        states=Object.fromEntries(io.inputs.filter(i=>i.name!=='x').map(i=>[i.name,outputs['new_'+i.name]]));
        context.nativeDeliver(data.id,result,null);
      }catch(error){context.nativeDeliver(data.id,null,String(error));}
      finally{
        x?.dispose();
        for(const tensor of Object.values(outputs??{}))if(!Object.values(states).includes(tensor))tensor.dispose();
      }
    });
  }});
  vm.runInContext(nativeBytes.toString(),context,{filename:'packaged-native.js'});
  try{
    await context.nativeOperation('initialize',{...settings,corpus,io});
    for(let at=0;at<pcm.length;at+=7680){
      const chunk=pcm.subarray(at,Math.min(pcm.length,at+7680));samples=at+chunk.length;
      let result=await context.nativeOperation('feed',{pcm:Array.from(chunk)});
      while(result.correction.phase!=='idle')result=await context.nativeOperation('correct',{action:'dismiss'});
    }
    await context.nativeOperation('stop',{});
    await inference;
    return {events,evidence};
  }finally{for(const tensor of Object.values(states))tensor.dispose();await engine.release();}
}
await mkdir(output); // Refuse overwriting earlier evidence.
const started=Date.now();
const upstream=await original();
await writeFile(join(output,'upstream.json'),JSON.stringify(upstream,null,2));
const wrapped=await packaged();
await writeFile(join(output,'packaged-js.json'),JSON.stringify(wrapped,null,2));
const common=e=>['word_progress','correction','correction_note','final_sequence'].includes(e.type);
const a=upstream.events.filter(common),b=wrapped.events.filter(common);
const summary={clipSha256:hash(input),samples:pcm.length,seconds:pcm.length/16000,
  upstreamCommit:baseline.upstream.commit,runtimeSha256:hash(nativeBytes),settings,
  comparison:'Original pinned core vs packaged JS bridge using SAME WebAssembly ONNX backend. Not Android-native or Dart-facade parity.',
  issuesUpstream:a.filter(e=>e.type==='correction'&&e.state.phase==='error').map(e=>e.state.issue),
  issuesPackaged:b.filter(e=>e.type==='correction'&&e.state.phase==='error').map(e=>e.state.issue),
  sharedEventsEqual:JSON.stringify(a)===JSON.stringify(b),elapsedMs:Date.now()-started,
  policy:'After each flagged feed, auto-dismiss to continue the comparison; terminal findings are closed, never counted as corrected.',
  accuracy:'Not computed. Human annotation of the actual spoken mistakes is required.'};
await writeFile(join(output,'summary.json'),JSON.stringify(summary,null,2));
console.log(JSON.stringify(summary,null,2));
