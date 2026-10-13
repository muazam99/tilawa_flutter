// Private diagnostic for the opt-in PROBE_NATIVE_BRIDGE Android build.
// Injects a JavaScript bridge error, not an Android renderer-process crash.
import { execFileSync } from 'node:child_process';

const adb = process.argv[2];
if (!adb) throw new Error('Usage: node recovery_bridge.mjs <adb-executable>');
const command = (...args) => execFileSync(adb, args, { encoding: 'utf8' }).trim();
const pid = command('shell', 'pidof', 'dev.qiyam.tilawa_bridge_probe');
if (!/^\d+$/.test(pid)) throw new Error('Expected one running private probe process');
const port = command('forward', 'tcp:0', `localabstract:webview_devtools_remote_${pid}`);
let socket;
try {
  let target;
  for (let attempt = 0; attempt < 30 && !target; attempt++) {
    try {
      const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = targets.find((item) => item.url.startsWith('http://127.0.0.1:') && item.url.endsWith('/index.html'));
    } catch { /* Runtime initialization may still be underway. */ }
    if (!target) await new Promise((resolve) => setTimeout(resolve, 500));
  }
  if (!target) throw new Error('No local runtime target found');
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  const result = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('CDP command timed out')), 5000);
    socket.addEventListener('message', (message) => {
      const reply = JSON.parse(message.data);
      if (reply.id !== 1) return;
      clearTimeout(timeout);
      if (reply.error || reply.result?.exceptionDetails) reject(new Error(JSON.stringify(reply)));
      else resolve(reply.result?.result?.value);
    });
  });
  socket.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: {
    returnByValue: true,
    expression: `(() => {
      if (typeof window.tilawaDispatch !== 'function') throw Error('Bridge not ready');
      const dispatch = window.tilawaDispatch;
      window.tilawaDispatch = request => {
        if (request.method !== 'feed') return dispatch(request);
        setTimeout(() => {
          TilawaSdk.postMessage(JSON.stringify({kind:'error',error:'Private injected JavaScript bridge failure'}));
          setTimeout(() => TilawaSdk.postMessage(JSON.stringify({kind:'event',event:{type:'raw_transcript',text:'late',confidence:1}})), 50);
        }, 100);
      };
      return 'pending-feed-fault-installed';
    })()`,
  } }));
  console.log(await result);
} finally {
  socket?.close();
  command('forward', '--remove', `tcp:${port}`);
}
