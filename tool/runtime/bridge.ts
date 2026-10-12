// SDK bridge protocol, pinned core baseline. Not the Phase 1 probe protocol.
import * as ort from 'onnxruntime-web/wasm';
import { createZipformerSession } from '@pinned/session';

let session: Awaited<ReturnType<typeof createZipformerSession>> | null = null;
let runtime: ort.InferenceSession | null = null;
let samples = 0;
let sequence: unknown[] | null = null;
let score: number | null = null;
let queue = Promise.resolve();
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
  transcript: ready().transcript, sequence, score });

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
      const [model, corpus, io] = await Promise.all([
        local('model.onnx').then(r => r.arrayBuffer()),
        local('corpus.json').then(r => r.json()), local('io.json').then(r => r.json()),
      ]);
      runtime = await ort.InferenceSession.create(model, { executionProviders: ['wasm'], graphOptimizationLevel: 'all' });
      session = await createZipformerSession({ session: runtime, Tensor: ort.Tensor,
        corpus, io, structural: false, slipHead: false,
        minWordFraction: Number(data.minWordFraction), enableFallback: data.enableFallback === true,
        fallbackMaxDistance: Number(data.fallbackMaxDistance), stayOnSurah: data.stayOnSurah === true,
        tailSeconds: Number(data.tailSeconds), debug: data.debug === true,
        onEvent(event) {
          if (event.type === 'final_sequence') { sequence = event.verses; score = event.confidence; }
          post({ kind: 'event', event });
        },
      });
      session.setMode('tracking');
      samples = 0; sequence = null; score = null;
      return snapshot();
    }
    case 'feed': {
      const bytes = Uint8Array.from(atob(String(data.pcm)), char => char.charCodeAt(0));
      if (bytes.length % 4) throw new Error('Incomplete float32 sample');
      const view = new DataView(bytes.buffer);
      const pcm = new Float32Array(bytes.length / 4);
      for (let i = 0; i < pcm.length; i++) pcm[i] = view.getFloat32(i * 4, true);
      await ready().feed(pcm);
      samples += pcm.length;
      return snapshot();
    }
    case 'stop': await ready().stop(); return snapshot();
    case 'reset': ready().reset(); samples = 0; sequence = null; score = null; return snapshot();
    case 'wordCount': {
      const surah = Number(data.surah), ayah = Number(data.ayah);
      if (!Number.isInteger(surah) || !Number.isInteger(ayah) || surah < 1 || surah > 114 || ayah < 1) {
        throw new Error('Invalid Quran reference');
      }
      const words = ready().wordCount(surah, ayah);
      if (!Number.isInteger(words) || words <= 0) throw new Error('Ayah not in the pinned corpus');
      return { words };
    }
    case 'dispose': {
      session = null;
      const previous = runtime; runtime = null;
      if (previous) await previous.release();
      return { disposed: true };
    }
    default: throw new Error(`Unknown operation ${method}`);
  }
}
(window as any).tilawaDispatch = (request: { id: number; method: string; data?: Record<string, unknown> }) => {
  queue = queue.then(async () => {
    try { post({ kind: 'reply', id: request.id, result: await dispatch(request.method, request.data) }); }
    catch (error) { post({ kind: 'reply', id: request.id, error: String(error) }); }
  });
};
window.addEventListener('error', event => post({ kind: 'error', error: event.message }));
window.addEventListener('unhandledrejection', event => post({ kind: 'error', error: String(event.reason) }));
post({ kind: 'ready' });
