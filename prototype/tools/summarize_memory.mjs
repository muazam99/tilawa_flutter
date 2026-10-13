// Private bounded RAM comparison. PSS pairs are sequential samples, not true peaks.
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
const labels = process.argv.slice(2);
if (!labels.length || labels.some(x => !/^[a-z0-9-]+$/.test(x))) throw Error('Provide evidence labels');
const median = values => {
  const sorted = values.toSorted((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length ? sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2 : null;
};
for (const label of labels) {
  const root = resolve('prototype/.cache/validation-evidence', label);
  const records = (await readFile(`${root}-memory.jsonl`, 'utf8')).trim().split('\n').map(JSON.parse);
  const events = await readFile(`${root}-events.log`, 'utf8');
  const valid = records.filter(r => r.measurements?.length && r.measurements.every(m => Number.isFinite(m.pssKiB)));
  const total = r => r.measurements.reduce((sum, m) => sum + m.pssKiB, 0);
  const baselineRows = valid.filter(r => r.stage === 'profile-baseline');
  if (baselineRows.some(r => r.measurements.length !== 1)) {
    throw Error(`${label}: decoder/browser present in app-only baseline; cannot compare SDK increment`);
  }
  const baseline = median(baselineRows.map(total));
  if (baseline === null) throw Error(`${label}: missing app-only baseline`);
  const stages = {};
  for (const stage of new Set(valid.map(r => r.stage).filter(x => x?.startsWith('profile-')))) {
    const rows = valid.filter(r => r.stage === stage);
    const totals = rows.map(total);
    stages[stage] = { samples: rows.length, medianTotalKiB: median(totals),
      medianIncrementKiB: median(totals) - baseline, sampledMaxTotalKiB: Math.max(...totals),
      maxSwapKiB: Math.max(...rows.map(r=>r.measurements.reduce((n,m)=>n+(m.swapPssKiB??0),0))) };
  }
  const steady = valid.filter(r => /^profile-\d+-steady$/.test(r.stage));
  const active = valid.filter(r => /^profile-\d+-(ready|processing|steady|reset)$/.test(r.stage));
  const loading = valid.filter(r => /^profile-\d+-opening$/.test(r.stage));
  const passages = [...events.matchAll(/TILAWA_PERF PASSAGE (\{.*\})/g)].map(m=>JSON.parse(m[1]));
  const opens = [...events.matchAll(/TILAWA_PERF PROFILE_OPEN (\{.*\})/g)].map(m=>JSON.parse(m[1]));
  const progressFingerprints = [...events.matchAll(/TILAWA_PERF PROGRESS_FINGERPRINT (\{.*\})/g)].map(m=>JSON.parse(m[1]));
  const result = {label, completed: events.includes('TILAWA_PERF COMPLETE '),
    failed: events.includes('TILAWA_PERF ERROR '), baselineKiB: baseline,
    recognitionEvidenceComplete: opens.length > 0 && passages.length === opens.length &&
      passages.every(p => p.expectedSequence && p.finalization === 'complete' && p.processedSamples === p.inputSamples),
    progressFingerprints,
    steadyIncrementKiB: median(steady.map(total)) === null ? null : median(steady.map(total)) - baseline,
    activeSampledMaxIncrementKiB: active.length ? Math.max(...active.map(total)) - baseline : null,
    loadingSampledMaxIncrementKiB: loading.length ? Math.max(...loading.map(total)) - baseline : null,
    temperaturesTenthsC: [...new Set(valid.map(r=>r.batteryTemperatureTenthsC))],
    passages: passages.map(p=>({id:p.id, expectedSequence:p.expectedSequence, progress:p.progress,
      finalization:p.finalization, samples:p.processedSamples, elapsedMs:p.elapsedMs})), opens, stages};
  await writeFile(`${root}-summary.json`, JSON.stringify(result,null,2));
  console.log(JSON.stringify(result));
}
