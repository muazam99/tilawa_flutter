// Maintainer-only generation from verified Phase 1 inputs. Consumers need no npm.
import { build } from '../prototype/node_modules/esbuild/lib/main.js';
import { createHash } from 'node:crypto';
import { readFile, mkdir, copyFile, writeFile, readdir } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const upstream = join(root, 'prototype/.cache/upstream');
const baseline = JSON.parse(await readFile(join(root, 'prototype/baseline.json'), 'utf8'));
// The preparation cache must have been verified against an immutable Git tree.
// Recheck all core sources against that same tree before generating distribution code.
const response = await fetch(`https://api.github.com/repos/yazinsai/tilawa/git/trees/${baseline.upstream.commit}?recursive=1`);
if (!response.ok) throw new Error(`Pinned tree: ${response.status}`);
const tree = await response.json();
if (tree.truncated) throw new Error('Truncated pinned tree');
for (const entry of tree.tree.filter(e => e.type === 'blob' && e.path.startsWith('packages/core/src/'))) {
  const bytes = await readFile(join(upstream, entry.path));
  const actual = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
  if (actual !== entry.sha) throw new Error(`Source identity mismatch: ${entry.path}`);
}
const output = join(root, 'assets/runtime');
await mkdir(output, { recursive: true });
// Native dependency licenses are checked-in distribution inputs. Refuse to
// regenerate a bundle that silently loses their retained copyright notices.
for (const name of ['QUICKJS_ENGINE_LICENSE', 'FLUTTER_ONNXRUNTIME_LICENSE']) {
  await readFile(join(output, name));
}
await build({ entryPoints: [join(root, 'tool/runtime/native_bridge.ts')],
  outfile: join(output, 'native.js'), bundle: true, format: 'iife', platform: 'neutral',
  target: ['es2020'], legalComments: 'eof',
  alias: { '@pinned/session': join(upstream, 'packages/core/src/recitation/session.ts') } });
await build({ entryPoints: [join(root, 'tool/runtime/bridge.ts')],
  outfile: join(output, 'bridge.js'), bundle: true, format: 'esm', platform: 'browser',
  target: ['es2022'], legalComments: 'eof',
  nodePaths: [join(root, 'prototype/node_modules')],
  alias: { '@pinned/session': join(upstream, 'packages/core/src/recitation/session.ts') } });
await copyFile(join(root, 'tool/runtime/index.html'), join(output, 'index.html'));
for (const name of ['ort-wasm-simd-threaded.mjs', 'ort-wasm-simd-threaded.wasm']) {
  await copyFile(join(root, 'prototype/node_modules/onnxruntime-web/dist', name), join(output, name));
}
for (const name of ['TILAWA_LICENSE', 'TILAWA_NOTICE.md', 'NPL-1.2.txt',
  'ONNXRUNTIME_LICENSE', 'ONNXRUNTIME_ThirdPartyNotices.txt']) {
  await copyFile(join(root, 'prototype/app/assets/runtime', name), join(output, name));
}
const artifacts = [];
for (const name of await readdir(output)) {
  if (name === 'manifest.json') continue;
  const bytes = await readFile(join(output, name));
  artifacts.push({ name, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
}
await writeFile(join(output, 'manifest.json'), JSON.stringify({
  upstreamCommit: baseline.upstream.commit, ortVersion: '1.24.2', quickjsVersion: '0.1.6', artifacts,
}, null, 2) + '\n');
console.log(`SDK runtime generated: ${artifacts.length} artifacts; no model/corpus/audio included.`);
