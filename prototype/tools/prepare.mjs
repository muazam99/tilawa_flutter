// Phase 1 only: fetch pinned source/assets and bundle a fully local runtime.
import { build } from 'esbuild';
import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { copyFile, mkdir, readFile, readdir, rename, stat } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const baseline = JSON.parse(await readFile(join(root, 'baseline.json'), 'utf8'));
const source = join(root, '.cache/upstream');
const output = join(root, 'app/assets/runtime');
const raw = `https://raw.githubusercontent.com/yazinsai/tilawa/${baseline.upstream.commit}/`;

async function hash(file, algorithm = 'sha256') {
  const digest = createHash(algorithm);
  let bytes = 0;
  for await (const chunk of createReadStream(file)) {
    digest.update(chunk);
    bytes += chunk.length;
  }
  return { digest: digest.digest('hex'), bytes };
}

async function download(url, file, expected) {
  await mkdir(dirname(file), { recursive: true });
  try {
    const cached = await hash(file);
    if (expected && cached.digest === expected.sha256 && cached.bytes === expected.bytes) return;
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const response = await fetch(url);
  if (!response.ok || !response.body) throw new Error(`${response.status}: ${url}`);
  const partial = `${file}.partial`;
  await pipeline(Readable.fromWeb(response.body), createWriteStream(partial));
  if (expected) {
    const actual = await hash(partial);
    if (actual.digest !== expected.sha256 || actual.bytes !== expected.bytes) {
      throw new Error(`Integrity mismatch for ${file}: ${JSON.stringify(actual)}`);
    }
  }
  await rename(partial, file);
}

await mkdir(output, { recursive: true });
const response = await fetch(`https://api.github.com/repos/yazinsai/tilawa/git/trees/${baseline.upstream.commit}?recursive=1`);
if (!response.ok) throw new Error(`GitHub tree: ${response.status}`);
const tree = await response.json();
if (tree.truncated) throw new Error('GitHub returned a truncated tree');
const files = tree.tree.filter((entry) => entry.type === 'blob' &&
  (entry.path.startsWith('packages/core/src/') || ['LICENSE', 'NOTICE.md', 'packages/core/package.json',
    'lab/benchmark/test_corpus/manifest.json'].includes(entry.path)));
for (let i = 0; i < files.length; i += 8) {
  await Promise.all(files.slice(i, i + 8).map(async (entry) => {
    const target = join(source, entry.path);
    await download(raw + entry.path, target);
    // Verify immutable Git blob identity, not just a successful HTTP response.
    const data = await readFile(target);
    const blob = createHash('sha1').update(`blob ${data.length}\0`).update(data).digest('hex');
    if (blob !== entry.sha) throw new Error(`Git blob mismatch: ${entry.path}`);
  }));
}
console.log(`Verified ${files.length} source files at ${baseline.upstream.commit}`);
for (const asset of baseline.assets) {
  await download(asset.url, join(output, asset.file), asset);
  console.log(`Verified ${asset.file}: ${asset.sha256}`);
}
for (const name of ['LICENSE', 'NOTICE.md']) await copyFile(join(source, name), join(output, `TILAWA_${name}`));
await download('https://raw.githubusercontent.com/microsoft/onnxruntime/v1.24.2/LICENSE', join(output, 'ONNXRUNTIME_LICENSE'));
await download('https://raw.githubusercontent.com/microsoft/onnxruntime/v1.24.2/ThirdPartyNotices.txt', join(output, 'ONNXRUNTIME_ThirdPartyNotices.txt'));
const ortDist = join(root, 'node_modules/onnxruntime-web/dist');
for (const name of await readdir(ortDist)) {
  if (['ort-wasm-simd-threaded.mjs', 'ort-wasm-simd-threaded.wasm'].includes(name)) {
    await copyFile(join(ortDist, name), join(output, name));
  }
}
const manifest = JSON.parse(await readFile(join(source, 'lab/benchmark/test_corpus/manifest.json'), 'utf8'));
const samples = Array.isArray(manifest) ? manifest : manifest.samples;
const selectedIds = ['ref_112001', 'multi_113_001_005'];
for (const id of selectedIds) {
  const sample = samples.find((entry) => entry.id === id);
  if (!sample) throw new Error(`Missing pinned sample ${id}`);
  const path = `lab/benchmark/test_corpus/${sample.file}`;
  const blob = tree.tree.find((entry) => entry.path === path);
  if (!blob) throw new Error(`Missing sample file ${path}`);
  const file = join(output, id + '.audio');
  await download(raw + path, file);
  const data = await readFile(file);
  const actual = createHash('sha1').update(`blob ${data.length}\0`).update(data).digest('hex');
  if (actual !== blob.sha) throw new Error(`Sample Git blob mismatch: ${id}`);
  console.log(`Sample ${id}: ${sample.file}, expected ${JSON.stringify(sample.expected_verses)}, blob ${blob.sha}`);
}
await build({
  entryPoints: [join(root, 'web/bridge.ts')],
  outfile: join(output, 'bridge.js'),
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: ['es2022'],
  alias: { '@pinned/session': join(source, 'packages/core/src/recitation/session.ts') },
  legalComments: 'eof',
  sourcemap: false,
});
await copyFile(join(root, 'web/index.html'), join(output, 'index.html'));
const total = await Promise.all((await readdir(output)).map(async (name) => (await stat(join(output, name))).size));
console.log(`Local runtime ready: ${(total.reduce((a, b) => a + b, 0) / 1048576).toFixed(1)} MiB`);
