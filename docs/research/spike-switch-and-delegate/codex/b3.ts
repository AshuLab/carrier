// B3: what each sandbox x approval-policy lets the agent do without asking. Every approval is declined.
// Runs against a scripted fake model (mock.ts): the real account was at its usage limit. The commands are the ones a model would send as `exec_command`.
import { appendFileSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { App, tmp, here } from './lib.ts';
import { startMock } from './mock.ts';

const out = join(here, 'logs', 'b3-summary.txt');
writeFileSync(out, '');
const say = (...a: unknown[]) => { const line = a.map((x) => (typeof x === 'string' ? x : JSON.stringify(x))).join(' '); console.log(line); appendFileSync(out, line + '\n'); };

const uid = Math.random().toString(36).slice(2, 8);
const outTmp = `/tmp/cdxb-out-${uid}`; // a unique folder under /tmp, outside the working folder
const outVar = `/var/tmp/cdxb-out-${uid}`; // a unique folder outside the working folder AND outside the sandbox's usual temp roots
const patch = (f: string) => `apply_patch <<'EOF'\n*** Begin Patch\n*** Add File: ${f}\n+hi\n*** End Patch\nEOF`;

type Probe = { id: string; cmd: string; check?: string };
const probes = (folder: string): Probe[] => [
  { id: '1 write a.txt in the folder (shell redirect)', cmd: 'printf hi > a.txt', check: join(folder, 'a.txt') },
  { id: '1b write a1.txt in the folder (apply_patch)', cmd: patch('a1.txt'), check: join(folder, 'a1.txt') },
  { id: '2 write b.txt in a new folder under /tmp', cmd: `mkdir -p ${outTmp}/new && printf hi > ${outTmp}/new/b.txt`, check: `${outTmp}/new/b.txt` },
  { id: '2b write b.txt in a new folder under /var/tmp', cmd: `mkdir -p ${outVar}/new && printf hi > ${outVar}/new/b.txt`, check: `${outVar}/new/b.txt` },
  { id: '3 curl -sI https://example.com | head -1', cmd: 'curl -sI https://example.com | head -1' },
  { id: '4 ls', cmd: 'ls' },
];

try {
  for (const sandbox of ['read-only', 'workspace-write']) for (const policy of ['untrusted', 'on-request', 'never']) {
    const folder = tmp('cdxb-');
    const mock = await startMock();
    const app = new App(`b3-${sandbox}-${policy}`, folder, mock.args);
    app.mocked = true;
    const asked: any[] = [];
    app.handler = (method, p) => {
      if (method === 'item/commandExecution/requestApproval') { asked.push({ method, command: String(p.command ?? '').split('\n')[0].slice(0, 70), reason: p.reason ?? null, decisions: p.availableDecisions?.map((d: any) => (typeof d === 'string' ? d : Object.keys(d)[0])) }); return { decision: 'decline' }; }
      if (method === 'item/fileChange/requestApproval') { asked.push({ method, reason: p.reason ?? null, grantRoot: p.grantRoot ?? null }); return { decision: 'decline' }; }
      if (method === 'item/permissions/requestApproval') { asked.push({ method, permissions: p.permissions }); return { permissions: {}, scope: 'turn' }; }
      if (method === 'mcpServer/elicitation/request') { asked.push({ method }); return { action: 'decline', content: null }; }
      asked.push({ method, unexpected: true });
      throw new Error('unexpected ' + method);
    };
    try {
      await app.init();
      const r = await app.request('thread/start', { cwd: folder, approvalPolicy: policy, sandbox, model: 'mock-model' });
      for (const pr of probes(folder)) {
        asked.length = 0;
        mock.state.requests.length = 0;
        mock.state.script = [{ call: 'exec_command', args: { cmd: pr.cmd } }, { say: 'done' }];
        const res = await app.turn(r.thread.id, `probe ${pr.id}`, {}, 60_000);
        const items = res.notes.filter((n) => n.method === 'item/completed' && ['commandExecution', 'fileChange'].includes(n.params.item.type)).map((n) => n.params.item);
        const it = items[0];
        const row = {
          sandbox, policy, probe: pr.id,
          asked: asked.map((a) => ({ ...a })),
          item: it ? { type: it.type, status: it.status, exitCode: it.exitCode ?? null, out: String(it.aggregatedOutput ?? '').replace(/\s+/g, ' ').slice(0, 140) } : null,
          onDisk: pr.check === undefined ? null : existsSync(pr.check),
          modelSaw: (mock.state.requests.at(-1)?.outputs.at(-1) ?? null)?.replace(/\\n/g, ' ').slice(0, 260) ?? null,
          turn: res.completed.turn.status,
        };
        say('ROW', row);
      }
    } finally {
      await app.close(); await mock.close(); rmSync(folder, { recursive: true, force: true });
      rmSync(outTmp, { recursive: true, force: true }); rmSync(outVar, { recursive: true, force: true });
    }
  }
} finally { rmSync(outTmp, { recursive: true, force: true }); rmSync(outVar, { recursive: true, force: true }); }
