// Private ADB evidence collector. Sequential app/renderer samples are not peaks.
import { execFileSync, spawn } from 'node:child_process';
import { mkdir, writeFile, appendFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const adb = process.argv[2];
const label = process.argv[3];
if (!adb || !/^[a-z0-9-]+$/.test(label ?? '')) throw new Error('Usage: node capture_validation.mjs <adb-executable> <label>');
const intervalSeconds = Number(process.argv[4] ?? 30);
const deadlineSeconds = Number(process.argv[5] ?? 900);
const targetPackage = process.argv[7] === 'package'
  ? 'dev.tilawa.tilawa_flutter_package_check' : 'dev.qiyam.tilawa_bridge_probe';
if (!Number.isInteger(intervalSeconds) || intervalSeconds < 1 || intervalSeconds > 30 ||
    !Number.isInteger(deadlineSeconds) || deadlineSeconds < 60 || deadlineSeconds > 900) {
  throw new Error('Sampling interval must be1..30s and deadline60..900s');
}
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = join(root, '.cache/validation-evidence');
await mkdir(output, { recursive: true });
const logFile = join(output, `${label}-events.log`);
const memoryFile = join(output, `${label}-memory.jsonl`);
await writeFile(logFile, '');
await writeFile(memoryFile, '');
const command = (...args) => execFileSync(adb, args, { encoding: 'utf8', timeout: 15000, maxBuffer: 4 * 1024 * 1024 }).trim();
let sampling = false, finished = false;
let stage = 'launch';
let debugPort;
const collectedStages = new Set();
async function inspectHeap(appPid, sampledStage) {
  if (process.argv[7] !== 'heap-gc') return null;
  debugPort ??= command('forward', 'tcp:0', `localabstract:webview_devtools_remote_${appPid}`);
  const targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`, {
    signal: AbortSignal.timeout(3000),
  })).json();
  const output = [];
  for (const target of targets.filter(value => value.type === 'page')) {
    const socket = new WebSocket(target.webSocketDebuggerUrl);
    try {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('CDP connect timeout')), 3000);
        socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
        socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('CDP connect failed')); }, { once: true });
      });
      let nextId = 0;
      const call = method => new Promise((resolve, reject) => {
        const id = ++nextId;
        const timer = setTimeout(() => { socket.removeEventListener('message', receive); reject(new Error('CDP call timeout')); }, 3000);
        function receive(message) {
          const reply = JSON.parse(message.data);
          if (reply.id !== id) return;
          clearTimeout(timer);
          socket.removeEventListener('message', receive);
          if (reply.error) reject(new Error(JSON.stringify(reply.error)));
          else resolve(reply.result);
        }
        socket.addEventListener('message', receive);
        socket.send(JSON.stringify({ id, method }));
      });
      const before = await call('Runtime.getHeapUsage');
      const collect = sampledStage.endsWith('-disposed') && !collectedStages.has(sampledStage);
      if (collect) await call('HeapProfiler.collectGarbage');
      output.push({ targetId: target.id, url: target.url, before, forcedGc: collect,
        after: collect ? await call('Runtime.getHeapUsage') : null });
    } finally { socket.close(); }
  }
  if (sampledStage.endsWith('-disposed')) collectedStages.add(sampledStage);
  return output;
}
async function sample() {
  if (sampling || finished) return;
  sampling = true;
  const sampledStage = stage;
  const startedAt = new Date().toISOString();
  try {
    const appPid = command('shell', 'pidof', targetPackage);
    if (!/^\d+$/.test(appPid)) throw new Error('Probe not running');
    const services = command('shell', 'dumpsys', 'activity', 'services', targetPackage);
    const associated = new Map();
    for (const block of services.split(/(?=\* ServiceRecord)/)) {
      if (!block.includes(targetPackage)) continue;
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
      measurements.push({ at: new Date().toISOString(), pid: Number(pid), name, pssKiB: pss ? Number(pss[1]) : null,
        rssKiB: rss ? Number(rss[1]) : null, swapPssKiB: swap ? Number(swap[1]) : null });
    }
    const battery = command('shell', 'dumpsys', 'battery');
    let heap;
    try { heap = await inspectHeap(appPid, sampledStage); }
    catch (error) { heap = { error: String(error) }; }
    await appendFile(memoryFile, JSON.stringify({ at: new Date().toISOString(), startedAt, stage: sampledStage,
      rendererAssociation: associated.size ? 'service-owned-by-probe' : 'unresolved-or-not-yet-created',
      measurements, totalPssKiB: measurements.reduce((sum, value) => sum + (value.pssKiB ?? 0), 0),
      totalSwapPssKiB: measurements.reduce((sum, value) => sum + (value.swapPssKiB ?? 0), 0),
      heap, batteryTemperatureTenthsC: Number(battery.match(/temperature:\s*(\d+)/)?.[1] ?? 0),
    }) + '\n');
  } catch (error) {
    await appendFile(memoryFile, JSON.stringify({ at: new Date().toISOString(), error: `${error}` }) + '\n');
  } finally { sampling = false; }
}
if (process.argv[6] === 'launch') {
  command('shell', 'am', 'force-stop', targetPackage);
  command('logcat', '-c');
  const activity = command('shell','cmd','package','resolve-activity','--brief',targetPackage)
    .split(/\r?\n/).find(line=>/^\S+\/\S+$/.test(line));
  if (!activity) throw Error('No resolved launcher activity for '+targetPackage);
  command('shell', 'am', 'start', '-n', activity);
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
  if (debugPort) {
    command('forward', '--remove', `tcp:${debugPort}`);
    debugPort = null;
  }
}
logcat.stdout.on('data', (chunk) => {
  buffer += chunk.toString();
  const lines = buffer.split('\n');
  buffer = lines.pop();
  for (const line of lines) {
    if (!line.includes('TILAWA_PERF ') && !line.includes('TILAWA_NATIVE_STATS ') && !line.includes('TILAWA_PACKAGE ')) continue;
    writes = writes.then(() => appendFile(logFile, line + '\n'));
    console.log(line);
    const checkpoint = line.match(/TILAWA_PERF MEMORY (\{.*\})/);
    if (checkpoint) {
      stage = JSON.parse(checkpoint[1]).stage;
      void sample();
    }
    if (/TILAWA_(PERF|PACKAGE) (COMPLETE|ERROR) /.test(line)) finish();
  }
});
logcat.on('error', (error) => { console.error(error); finish(); });
logcat.on('close', async () => { await writes; process.exitCode = 0; });
process.on('SIGINT', finish);
const deadline = setTimeout(finish, deadlineSeconds * 1000);
timer = setInterval(() => { void sample(); }, intervalSeconds * 1000);
await sample();
