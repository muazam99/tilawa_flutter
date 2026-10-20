// SDK bridge protocol, pinned core baseline. Not the Phase 1 probe protocol.
import * as ort from 'onnxruntime-web/wasm';
import { createZipformerSession } from '@pinned/session';
import { correct, setExpected, stop, structuralOptions, WordEvidencePublisher } from './correction';

let session: Awaited<ReturnType<typeof createZipformerSession>> | null = null;
let runtime: ort.InferenceSession | null = null;
let samples = 0;
let sequence: unknown[] | null = null;
let score: number | null = null;
let queue = Promise.resolve();
let epoch = '';
let evidence: WordEvidencePublisher;
const post = (value: unknown) => (window as any).TilawaSdk.postMessage(JSON.stringify(value));
const local = async (name: string) => {
  const response = await fetch(new URL(name, location.href));
  if (!response.ok) throw new Error(`Local asset ${name}: ${response.status}`);
  return response;
};
const ready = () => {
  if (!session) throw new Error('Runtime is not initialized');
  return session;
};
const snapshot = () => ({ samples, state: ready().engineState,
  transcript: ready().transcript, sequence, score, correction: ready().correction.state });

async function dispatch(method: string, data: Record<string, unknown> = {}) {
  switch (method) {
    case 'initialize': {
      if (runtime || session) throw new Error('Runtime already initialized');
      if (typeof BigInt64Array === 'undefined' || typeof WebAssembly === 'undefined') {
        throw new Error('BigInt64Array and WebAssembly are required');
      }
      ort.env.wasm.numThreads = 1;
      ort.env.wasm.proxy = false;
      ort.env.wasm.wasmPaths = new URL('./', location.href).href;
      const { loadMode, ...diagnosticOptions } = (data.sessionOptions ?? {}) as
        ort.InferenceSession.SessionOptions & { loadMode?: string };
      const options: ort.InferenceSession.SessionOptions = {
        executionProviders: ['wasm'], graphOptimizationLevel: 'all', ...diagnosticOptions,
      };
      let corpus, io;
      if (loadMode === 'url') {
        // ORT owns the temporary fetch buffer; do not retain a second model
        // ArrayBuffer while parsing the corpus and constructing the tracker.
        runtime = await ort.InferenceSession.create(new URL('model.onnx', location.href).href, options);
        [corpus, io] = await Promise.all([
          local('corpus.json').then(r => r.json()), local('io.json').then(r => r.json()),
        ]);
      } else {
        const loaded = await Promise.all([
          local('model.onnx').then(r => r.arrayBuffer()),
          local('corpus.json').then(r => r.json()), local('io.json').then(r => r.json()),
        ]);
        runtime = await ort.InferenceSession.create(loaded[0], options);
        [corpus, io] = loaded.slice(1);
      }
      session = await createZipformerSession({ session: runtime, Tensor: ort.Tensor,
        corpus, io, structural: structuralOptions(data.structuralCorrection), slipHead: false,
        minWordFraction: Number(data.minWordFraction), enableFallback: data.enableFallback === true,
        fallbackMaxDistance: Number(data.fallbackMaxDistance), stayOnSurah: data.stayOnSurah === true,
        tailSeconds: Number(data.tailSeconds), debug: data.debug === true,
        onEvent(event) {
          if (event.type === 'final_sequence') { sequence = event.verses; score = event.confidence; }
          post({ kind: 'event', epoch, event });
        },
      });
      session.setMode(data.mode === 'correction' ? 'correction' : 'tracking');
      setExpected(session, data.expectedPassage);
      evidence = new WordEvidencePublisher(data.wordEvidence === true,
        event => post({ kind: 'event', epoch, event }), corpus);
      evidence.setExpected(data.expectedPassage);
      samples = 0; sequence = null; score = null;
      return snapshot();
    }
    case 'feed': {
      const bytes = Uint8Array.from(atob(String(data.pcm)), char => char.charCodeAt(0));
      if (bytes.length % 4) throw new Error('Incomplete float32 sample');
      const view = new DataView(bytes.buffer);
      const pcm = new Float32Array(bytes.length / 4);
      for (let i = 0; i < pcm.length; i++) pcm[i] = view.getFloat32(i * 4, true);
      if (ready().correction.state.phase === 'error' || ready().correction.state.phase === 'corrected') {
        post({ kind: 'event', epoch, event: { type: 'audio_discarded', samples: pcm.length,
          reason: 'correction_awaiting_action' } });
      } else await ready().feed(pcm);
      samples += pcm.length;
      evidence.publish(ready());
      return snapshot();
    }
    case 'stop':
      evidence.publish(ready());
      await stop(ready(), () => evidence.publish(ready(), true));
      return snapshot();
    case 'reset': ready().reset(); evidence.reset(); samples = 0; sequence = null; score = null; return snapshot();
    case 'setExpected': setExpected(ready(), data.passage); evidence.setExpected(data.passage); return snapshot();
    case 'correct': correct(ready(), data.action); evidence.publish(ready()); return snapshot();
    case 'wordCount': {
      const surah = Number(data.surah), ayah = Number(data.ayah);
      if (!Number.isInteger(surah) || !Number.isInteger(ayah) || surah < 1 || surah > 114 || ayah < 1) return { words: 0 };
      const words = ready().wordCount(surah, ayah);
      return { words: Number.isInteger(words) && words > 0 ? words : 0 };
    }
    case 'dispose': {
      session = null;
      sequence = null; score = null; samples = 0;
      const previous = runtime; runtime = null;
      if (previous) await previous.release();
      return { disposed: true };
    }
    default: throw new Error(`Unknown operation ${method}`);
  }
}
(window as any).tilawaDispatch = (request: { id: number; epoch: string; method: string; data?: Record<string, unknown> }) => {
  queue = queue.then(async () => {
    try {
      if (request.method === 'initialize') epoch = request.epoch;
      else if (request.epoch !== epoch) throw new Error('Stale runtime owner');
      post({ kind: 'reply', epoch: request.epoch, id: request.id, result: await dispatch(request.method, request.data) });
    }
    catch (error) { post({ kind: 'reply', epoch: request.epoch, id: request.id, error: String(error) }); }
  });
};
window.addEventListener('error', event => post({ kind: 'error', error: event.message }));
window.addEventListener('unhandledrejection', event => post({ kind: 'error', error: String(event.reason) }));
post({ kind: 'ready' });
