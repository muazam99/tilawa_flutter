// No generated test bundle is written to disk. The pinned core remains untouched.
import { build } from '../prototype/node_modules/esbuild/lib/main.js';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const result = await build({
  entryPoints: [resolve(root, 'test/runtime_correction.test.ts')],
  bundle: true, write: false, platform: 'node', format: 'esm', target: 'node22',
  alias: { '@pinned/controller': resolve(root, 'prototype/.cache/upstream/packages/core/src/recitation/correction.ts'),
    '@pinned/session': resolve(root, 'prototype/.cache/upstream/packages/core/src/recitation/session.ts') },
  plugins: [{name:'pinned-test-aliases', setup(build) {
    build.onResolve({filter:/^@pinned\/(corpus|engine|search|phonemeCost|alignment|config|structural|structural-index)$/}, args => ({
      path: resolve(root, 'prototype/.cache/upstream/packages/core/src/recitation',
        args.path.slice('@pinned/'.length) + (args.path.endsWith('structural-index') ? '.json' : '.ts')),
    }));
  }}],
});
// Avoid printing an entire base64 module URL when an assertion fails.
const { createRequire } = await import('node:module');
const require = createRequire(import.meta.url);
const compiled = await build({
  stdin: {contents: new TextDecoder().decode(result.outputFiles[0].contents), resolveDir: root},
  bundle: false, write: false, platform:'node',format:'cjs',target:'node22',
});
new Function('require', new TextDecoder().decode(compiled.outputFiles[0].contents))(require);
