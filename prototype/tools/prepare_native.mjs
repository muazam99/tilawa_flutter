import { build } from '../node_modules/esbuild/lib/main.js';
import { resolve } from 'node:path';
import { numericKernelPatch } from '../../tool/runtime/numeric_kernel_patch.mjs';
const root = resolve('prototype');
await build({entryPoints:[resolve(root,'tools/native_bridge.ts')],
  outfile:resolve(root,'app/assets/runtime/native_probe.js'),bundle:true,format:'iife',
  platform:'neutral',target:'es2020',legalComments:'eof',
  alias:{'@pinned/session':resolve(root,'.cache/upstream/packages/core/src/recitation/session.ts')},
  plugins:[numericKernelPatch]});
console.log('Private native matching bridge generated; no ORT/WASM bundled.');