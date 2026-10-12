// Private feasibility protocol. This is deliberately not the future public API.
import * as ort from 'onnxruntime-web/wasm';
import { createZipformerSession } from '@pinned/session';

declare global {
  interface Window {
    TilawaProbe: { postMessage(message: string): void };
    probeDispatch(request: { id: number; method: string; data?: Record<string, unknown> }): void;
  }
}

let session: Awaited<ReturnType<typeof createZipformerSession>> | null = null;
let runtime: ort.InferenceSession | null = null;
let generation = 0;
let sequence = 0;
let samples = 0;
let inferenceCalls = 0;
let inferenceMs = 0;
let eventCounts: Record<string, number> = {};
let finalSequence: Array<{ surah: number; ayah: number }> = [];
let queue = Promise.resolve();

function post(message: Record<string, unknown>) {
  window.TilawaProbe.postMessage(JSON.stringify(message));
}

function observation(event: { type: string; [key: string]: unknown }) {
  eventCounts[event.type] = (eventCounts[event.type] ?? 0) + 1;
  if (event.type === 'final_sequence') finalSequence = event.verses as typeof finalSequence;
  post({ kind: 'event', generation, sequence: ++sequence, processedSamples: samples, event });
}

async function local(path: string) {
  const response = await fetch(new URL(path, location.href));
  if (!response.ok) throw new Error(`${path}: ${response.status}`);
  return response;
}

async function initialize() {
  if (session || runtime) throw new Error('Dispose the current runtime before initialization');
  if (typeof BigInt64Array === 'undefined' || typeof WebAssembly === 'undefined') {
    throw new Error('Required BigInt64Array/WebAssembly support is missing');
  }
  const requestedThreads = Number(new URL(location.href).searchParams.get('threads') ?? '1');
  if (![1, 2, 4].includes(requestedThreads)) throw new Error('Unsupported probe thread count');
  const isolated = globalThis.crossOriginIsolated === true;
  const sharedArrayBuffer = typeof SharedArrayBuffer !== 'undefined';
  const threads = isolated && sharedArrayBuffer ? requestedThreads : 1;
  ort.env.wasm.numThreads = threads;
  ort.env.wasm.proxy = false;
  ort.env.wasm.wasmPaths = new URL('./', location.href).href;
  const start = performance.now();
  const [model, corpus, io] = await Promise.all([
    local('model.onnx').then((response) => response.arrayBuffer()),
    local('corpus.json').then((response) => response.json()),
    local('io.json').then((response) => response.json()),
  ]);
  const native = await ort.InferenceSession.create(model, { executionProviders: ['wasm'], graphOptimizationLevel: 'all' });
  runtime = native;
  try {
    session = await createZipformerSession({
      session: {
        async run(feeds: Record<string, ort.Tensor>) {
          const begin = performance.now();
          const outputs = await native.run(feeds);
          inferenceMs += performance.now() - begin;
          inferenceCalls++;
          return outputs;
        },
      },
      Tensor: ort.Tensor,
      io,
      corpus,
      structural: false,
      debug: true,
      onEvent: observation,
    });
    reset();
    return { initializeMs: performance.now() - start, userAgent: navigator.userAgent,
      bigInt64: true, wasm: true, requestedThreads, threads, isolated, sharedArrayBuffer,
      inputs: native.inputNames.length, outputs: native.outputNames.length };
  } catch (error) {
    runtime = null;
    await native.release();
    throw error;
  }
}

function ready() {
  if (!session) throw new Error('Recognition runtime is not initialized');
  return session;
}

function reset() {
  ready().reset();
  generation++;
  sequence = samples = inferenceCalls = inferenceMs = 0;
  eventCounts = {};
  finalSequence = [];
  return { generation };
}

function stats() {
  return { generation, samples, audioSeconds: samples / 16000, inferenceCalls, inferenceMs, eventCounts, finalSequence,
    engineState: ready().engineState };
}

async function feed(pcm: Float32Array) {
  samples += pcm.length;
  await ready().feed(pcm);
}

function pcm16(encoded: string) {
  const bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
  if (bytes.length % 2) throw new Error('Incomplete PCM16 sample');
  const view = new DataView(bytes.buffer);
  const pcm = new Float32Array(bytes.length / 2);
  for (let i = 0; i < pcm.length; i++) pcm[i] = view.getInt16(i * 2, true) / 32768;
  return pcm;
}

async function replay(id: string, paced: boolean) {
  if (!['ref_112001', 'multi_113_001_005'].includes(id)) throw new Error('Unknown pinned sample');
  reset();
  const bytes = await (await local(`${id}.audio`)).arrayBuffer();
  const context = new AudioContext();
  let decoded: AudioBuffer;
  try { decoded = await context.decodeAudioData(bytes); }
  finally { await context.close(); }
  const off = new OfflineAudioContext(1, Math.ceil(decoded.duration * 16000), 16000);
  const source = off.createBufferSource();
  source.buffer = decoded;
  source.connect(off.destination);
  source.start();
  const pcm = (await off.startRendering()).getChannelData(0);
  const begin = performance.now();
  const chunk = 7680; // 480 ms, upstream recommended chunk size.
  for (let i = 0; i < pcm.length; i += chunk) {
    await feed(pcm.subarray(i, Math.min(i + chunk, pcm.length)));
    if (paced) {
      const wait = Math.min(i + chunk, pcm.length) / 16 - (performance.now() - begin);
      if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    }
  }
  await ready().stop();
  const elapsedMs = performance.now() - begin;
  const expected = id === 'ref_112001' ? '112:1' : '113:1,113:2,113:3,113:4,113:5';
  const actual = finalSequence.map((verse) => `${verse.surah}:${verse.ayah}`).join(',');
  const parity = actual === expected && (eventCounts.word_progress ?? 0) > 0;
  if (!parity) throw new Error(`Replay mismatch ${id}: expected [${expected}], got [${actual}], progress ${eventCounts.word_progress ?? 0}`);
  return { id, paced, ...stats(), elapsedMs, processingRealTimeFactor: elapsedMs / (pcm.length / 16) };
}

async function dispatch(method: string, data: Record<string, unknown> = {}) {
  switch (method) {
    case 'initialize': return initialize();
    case 'reset': return reset();
    case 'feed': await feed(pcm16(String(data.pcm16))); return { samples };
    case 'stop': await ready().stop(); return stats();
    case 'sample': return replay(String(data.id), data.paced === true);
    case 'silence': reset(); await feed(new Float32Array(32000)); await ready().stop(); return stats();
    case 'dispose': {
      session = null;
      const previous = runtime;
      runtime = null;
      if (previous) await previous.release();
      return { disposed: true };
    }
    default: throw new Error(`Unknown operation: ${method}`);
  }
}

window.probeDispatch = (request) => {
  queue = queue.then(async () => {
    try {
      const result = await dispatch(request.method, request.data);
      post({ kind: 'reply', id: request.id, result });
    } catch (error) {
      post({ kind: 'reply', id: request.id, error: String(error), stack: error instanceof Error ? error.stack : undefined });
    }
  });
};
window.addEventListener('error', (event) => post({ kind: 'runtime_error', error: event.message }));
window.addEventListener('unhandledrejection', (event) => post({ kind: 'runtime_error', error: String(event.reason) }));
post({ kind: 'bridge_ready' });
