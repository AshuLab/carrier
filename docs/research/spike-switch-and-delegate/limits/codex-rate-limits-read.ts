// Spike D2: one read of `account/rateLimits/read` (no turn, no quota). Prints only the SHAPE and the reset times, never ids or the account.
// Run: node docs/research/spike-switch-and-delegate/limits/codex-rate-limits-read.ts
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';

const child = spawn('codex', ['app-server'], { stdio: ['pipe', 'pipe', 'ignore'] });
const send = (m: unknown) => child.stdin.write(`${JSON.stringify(m)}\n`);
const done = setTimeout(() => (console.log('TIMEOUT'), child.kill(), process.exit(1)), 20_000);
const shape = (v: unknown): unknown => (Array.isArray(v) ? v.map(shape) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, /id$/i.test(k) && k !== 'limitId' ? '<redacted>' : shape(x)])) : v);
createInterface({ input: child.stdout }).on('line', (line) => {
  const m = JSON.parse(line) as { id?: number; result?: any; error?: unknown };
  if (m.id === 1) {
    send({ method: 'initialized' });
    send({ id: 2, method: 'account/rateLimits/read' });
  } else if (m.id === 2) {
    clearTimeout(done);
    const r = m.result ?? {};
    console.log(JSON.stringify({ error: m.error, keys: Object.keys(r), rateLimits: shape(r.rateLimits), byLimitIdKeys: Object.keys(r.rateLimitsByLimitId ?? {}), ordinaryUsageAllowed: r.ordinaryUsageAllowed }, null, 1));
    for (const w of ['primary', 'secondary']) {
      const at = r.rateLimits?.[w]?.resetsAt;
      if (typeof at === 'number') console.log(w, 'resetsAt is', typeof at, 'epoch seconds ->', new Date(at * 1000).toISOString());
    }
    child.kill(); // the PID this script started
    process.exit(0);
  }
});
send({ id: 1, method: 'initialize', params: { clientInfo: { name: 'carrier-spike', title: 'spike', version: '0.0.0' } } });
