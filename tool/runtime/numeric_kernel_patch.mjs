import { readFile } from 'node:fs/promises';
export const numericKernelPatch = {name:'pinned-numeric-kernels', setup(build) {
    build.onLoad({filter:/recitation[\\/]alignment\.ts$/}, async ({path}) => {
      const source = await readFile(path,'utf8');
      const signature = '): Int32Array {';
      const at = source.indexOf(signature,source.indexOf('export function alignGlobal('));
      if(at < 0) throw Error('Pinned alignGlobal signature changed');
      const hook = `\n  const kernel = (globalThis as any).nativeAlignGlobal;
  if (typeof kernel === 'function') {
    return new Int32Array(kernel(heard.slice().buffer,ref.slice(from,to).buffer,table.matrix.buffer,from));
  }
`;
      return {contents:source.slice(0,at+signature.length)+hook+source.slice(at+signature.length),loader:'ts'};
    });
    build.onLoad({filter:/recitation[\\/]tracker\.ts$/}, async ({path}) => {
      const source = await readFile(path,'utf8');
      const start = source.indexOf('    const prev = this.column;',source.indexOf('private feedOne('));
      const end = source.indexOf('    this.column = next;',start);
      if(start < 0 || end < 0) throw Error('Pinned tracker kernel boundaries changed');
      const original = source.slice(start,end);
      const replacement = `    let next: Float32Array, bestCell: number, bestCost: number;
    if (typeof (globalThis as any).nativeTrackerKernel === 'function') {
      const self = this as any;
      const createKernel = (globalThis as any).nativeTrackerKernel;
      self.numericKernel ??= createKernel(
        this.ref.buffer,this.wordStarts.buffer,this.ayahAtStart.buffer,
        this.jumpExtra.buffer,this.table.matrix.buffer);
      const cursorAyah = this.cursorLocalWord < 0 ? -1 : this.corpus.wordAyah[this.firstWord + this.cursorLocalWord]!;
      const kernel = self.numericKernel;
      const result = kernel(this.column.buffer,this.table.id(h.ch),
        cursorAyah,this.cursorCell,this.cfg.jumpCost,this.cfg.repeatCost);
      next = new Float32Array(result[0]);bestCell=result[1];bestCost=result[2];
    }
    if (typeof (globalThis as any).nativeTrackerKernel !== 'function' || ((this as any).numericChecks ?? 0) < 2) {
${original}
      next = next; // assignments below publish fallback block locals
    }
`;
      // Rename the fallback locals so its original recurrence stays untouched.
      const fallback = original.replace('const next =','const fallbackNext =')
        .replace(/\bnext\b/g,'fallbackNext').replace(/\bbestCell\b/g,'fallbackCell')
        .replace(/\bbestCost\b/g,'fallbackCost');
      const contents = source.slice(0,start) + replacement.replace(original,fallback)
        .replace('next = next; // assignments below publish fallback block locals',
          `if (typeof (globalThis as any).nativeTrackerKernel !== 'function') {
            next = fallbackNext; bestCell = fallbackCell; bestCost = fallbackCost;
          } else {
            if(bestCell !== fallbackCell || bestCost !== fallbackCost || next.length !== fallbackNext.length) throw Error('Numeric tracker cursor mismatch');
            for(let i=0;i<next.length;i++) if(next[i] !== fallbackNext[i]) throw Error('Numeric tracker column mismatch at '+i);
            (this as any).numericChecks=((this as any).numericChecks??0)+1;
          }`) + source.slice(end);
      return {contents,loader:'ts'};
    });
  }};
