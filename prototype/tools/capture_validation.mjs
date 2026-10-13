// Private ADB evidence collector. Sequential app/renderer samples are not peaks.
import { execFileSync, spawn } from 'node:child_process';
import { mkdir, writeFile, appendFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const adb = process.argv[2];
const label = process.argv[3];
if (!adb || !/^[a-z0-9-]+$/.test(label ?? '')) throw new Error('Usage: node capture_validation.mjs <adb-executable> <label>');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = join(root, '.cache/validation-evidence');
await mkdir(output, { recursive: true });
const logFile = join(output, `${label}-events.log`);
const memoryFile = join(output, `${label}-memory.jsonl`);
await writeFile(logFile, '');
await writeFile(memoryFile, '');
const command = (...args) => execFileSync(adb, args, { encoding: 'utf8', timeout: 15000, maxBuffer: 4 * 1024 * 1024 }).trim();
let sampling = false, finished = false;
async function sample() {
  if (sampling || finished) return;
  sampling = true;
  try {
    const appPid = command('shell', 'pidof', 'dev.qiyam.tilawa_bridge_probe');
    if (!/^\d+$/.test(appPid)) throw new Error('Probe not running');
    const services = command('shell', 'dumpsys', 'activity', 'services', 'dev.qiyam.tilawa_bridge_probe');
    const associated = new Map();
    for (const block of services.split(/(?=\* ServiceRecord)/)) {
      if (!block.includes('dev.qiyam.tilawa_bridge_probe')) continue;
      for (const match of block.matchAll(/app=ProcessRecord\{[^}]*? (\d+):([^/}\s]+)/g)) {
        if (match[2].includes('sandboxed_process')) associated.set(match[1], match[2]);
      }
    }
    const pids = [[appPid, 'app'], ...[...associated.entries()].map(([pid, name]) => [pid, name])];
    const measurements = [];
    for (const [pid, name] of pids) {
      const memory = command('shell', 'dumpsys', 'meminfo', pid);
      const pss = memory.match(/TOTAL PSS:\s*(\d+)/);
      const rss = memory.match(/TOTAL RSS:\s*(\d+)/);
      const swap = memory.match(/TOTAL SWAP PSS:\s*(\d+)/);
      measurements.push({ pid: Number(pid), name, pssKiB: pss ? Number(pss[1]) : null,
        rssKiB: rss ? Number(rss[1]) : null, swapPssKiB: swap ? Number(swap[1]) : null });
    }
    const battery = command('shell', 'dumpsys', 'battery');
    await appendFile(memoryFile, JSON.stringify({ at: new Date().toISOString(),
      rendererAssociation: associated.size ? 'service-owned-by-probe' : 'unresolved-or-not-yet-created',
      measurements, batteryTemperatureTenthsC: Number(battery.match(/temperature:\s*(\d+)/)?.[1] ?? 0),
    }) + '\n');
  } catch (error) {
    await appendFile(memoryFile, JSON.stringify({ at: new Date().toISOString(), error: `${error}` }) + '\n');
  } finally { sampling = false; }
}
const logcat = spawn(adb, ['logcat', '-v', 'threadtime', '-s', 'flutter'], { stdio: ['ignore', 'pipe', 'pipe'] });
let buffer = '';
let writes = Promise.resolve();
let timer;
function finish() {
  if (finished) return;
  finished = true;
  clearInterval(timer);
  clearTimeout(deadline);
  logcat.kill();
}
logcat.stdout.on('data', (chunk) => {
  buffer += chunk.toString();
  const lines = buffer.split('\n');
  buffer = lines.pop();
  for (const line of lines) {
    if (!line.includes('TILAWA_PERF ')) continue;
    writes = writes.then(() => appendFile(logFile, line + '\n'));
    console.log(line);
    if (/TILAWA_PERF (COMPLETE|ERROR) /.test(line)) finish();
  }
});
logcat.on('error', (error) => { console.error(error); finish(); });
logcat.on('close', async () => { await writes; process.exitCode = 0; });
process.on('SIGINT', finish);
const deadline = setTimeout(finish, 15 * 60 * 1000);
timer = setInterval(() => { void sample(); }, 30000);
await sample();
