// Private developer metadata fixture. No SDK or Qiyam integration dependency.
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const prototype = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [pagesPath, juzPath] = process.argv.slice(2);
if (!pagesPath || !juzPath) throw new Error('Supply developer pages.json and juz.json paths');
const corpusBytes = await readFile(resolve(prototype, 'app/assets/runtime/corpus.json'));
const corpusSha256 = createHash('sha256').update(corpusBytes).digest('hex');
const baseline = JSON.parse(await readFile(resolve(prototype, 'baseline.json'), 'utf8'));
if (corpusSha256 !== baseline.assets.find(a => a.file === 'corpus.json').sha256) {
  throw new Error('Corpus identity mismatch');
}
const pageBytes = await readFile(pagesPath), juzBytes = await readFile(juzPath);
const pages = JSON.parse(pageBytes).pages, juzs = JSON.parse(juzBytes).juzs;
const corpus = JSON.parse(corpusBytes);
const ayahs = [];
for (const surah of corpus.surahs.filter(s => [112, 113].includes(s.n))) {
  for (const ayah of surah.ayahs) {
    const pageRefs = [], juzRefs = [];
    for (const page of Object.values(pages)) {
      const display = page.lines.flatMap(line => line.words).filter(
        word => word.surah === surah.n && word.ayah === ayah.n && !word.end);
      if (display.length) {
        // All fixture ayahs fit one page. Do not guess split-page word positions.
        if (display.length !== ayah.w.length) throw new Error(`Display count mismatch ${surah.n}:${ayah.n}`);
        pageRefs.push(page.page);
      }
    }
    for (const juz of juzs) {
      const range = juz.verse_mapping[String(surah.n)];
      if (!range) continue;
      const [first, last] = range.split('-').map(Number);
      if (ayah.n >= first && ayah.n <= last && !juzRefs.includes(juz.juz_number)) {
        juzRefs.push(juz.juz_number);
      }
    }
    if (pageRefs.length !== 1 || juzRefs.length !== 1) throw new Error('Fixture needs unambiguous references');
    ayahs.push({ surah: surah.n, ayah: ayah.n, pages: pageRefs, juz: juzRefs,
      // Labels are exactly the recognition corpus plain words. This fixture is
      // not an assertion that an independently tokenized display edition matches.
      words: ayah.w.map((word, index) => ({ index, id: `${surah.n}:${ayah.n}:${index + 1}`,
        text: word[2], pages: pageRefs, juz: juzRefs })) });
  }
}
const fixture = { descriptor: { version: 'private-corpus-display-v1',
  edition: 'Pinned corpus plain-word display; verified Madani page references',
  corpusSha256, segmentationId: `zipformer-wordInAyah-v1:${corpusSha256}` },
  provenance: { wordLabels: 'Pinned corpus.json w[2], NPL-1.2',
    layoutSource: 'Developer pages.json (derived from quran.com word line_number) and juz.json',
    pagesSha256: createHash('sha256').update(pageBytes).digest('hex'),
    juzSha256: createHash('sha256').update(juzBytes).digest('hex'),
    scope: 'Private 112/113 consumer fixture only; no default SDK edition or page-completion policy' }, ayahs };
await writeFile(resolve(prototype, 'app/assets/tracking_fixture.json'), JSON.stringify(fixture, null, 2) + '\n');
console.log(JSON.stringify(ayahs.map(a => ({ ayah: `${a.surah}:${a.ayah}`, words: a.words.length,
  pages: a.pages, juz: a.juz })), null, 2));
