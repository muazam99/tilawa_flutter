// Private pinned benchmark inputs. Never copied into the public example/archive.
import { createHash } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const baseline = JSON.parse(await readFile(join(root, 'baseline.json'), 'utf8'));
const commit = baseline.upstream.commit;
const response = await fetch(`https://api.github.com/repos/yazinsai/tilawa/git/trees/${commit}?recursive=1`);
if (!response.ok) throw new Error(`Pinned tree HTTP ${response.status}`);
const tree = await response.json();
if (tree.truncated) throw new Error('Truncated pinned tree');
const raw = `https://raw.githubusercontent.com/yazinsai/tilawa/${commit}/`;
const blobHash = (data) => createHash('sha1').update(`blob ${data.length}\0`).update(data).digest('hex');
async function verified(path) {
  const entry = tree.tree.find((item) => item.path === path && item.type === 'blob');
  if (!entry) throw new Error(`No pinned blob: ${path}`);
  const downloaded = await fetch(raw + path);
  if (!downloaded.ok) throw new Error(`HTTP ${downloaded.status}: ${path}`);
  const data = Buffer.from(await downloaded.arrayBuffer());
  if (blobHash(data) !== entry.sha) throw new Error(`Git blob mismatch: ${path}`);
  return { data, gitBlob: entry.sha };
}
const manifestPath = 'lab/benchmark/test_corpus/manifest.json';
const manifestBlob = await verified(manifestPath);
const manifest = JSON.parse(manifestBlob.data.toString('utf8'));
const ids = ['ref_001002', 'ref_002255', 'multi_036_001_005', 'multi_059_022_024',
  'multi_114_001_006', 'retasy_004', 'user_imran_23', 'multi_113_001_005'];
const output = join(root, 'app/assets/runtime');
await mkdir(output, { recursive: true });
const receipts = [];
for (const id of ids) {
  const sample = manifest.samples.find((item) => item.id === id);
  if (!sample) throw new Error(`Missing sample: ${id}`);
  const path = `lab/benchmark/test_corpus/${sample.file}`;
  const { data, gitBlob } = await verified(path);
  const name = `validation_${id}.audio`;
  await writeFile(join(output, `${name}.partial`), data);
  await rename(join(output, `${name}.partial`), join(output, name));
  receipts.push({ ...sample, asset: `assets/runtime/${name}`, upstreamPath: path,
    gitBlob, bytes: data.length, sha256: createHash('sha256').update(data).digest('hex') });
  console.log(`${id} bytes=${data.length} blob=${gitBlob} expected=${JSON.stringify(sample.expected_verses)} alternatives=${JSON.stringify(sample.also_accept ?? [])}`);
}
await writeFile(join(output, 'validation_samples.json'), JSON.stringify({
  upstreamCommit: commit, manifestGitBlob: manifestBlob.gitBlob,
  distribution: 'Private verification only; benchmark redistribution terms not finalized.',
  samples: receipts,
}, null, 2));
