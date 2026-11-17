// B7: is workspace-write's reach beyond the folder the same when the working folder is NOT under /tmp?
// The folder is a scratch folder inside this spike folder (removed at the end). Scripted fake model; real app-server.
import { appendFileSync, existsSync, mkdirSync, rmSync, writeFileSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { App, here } from './lib.ts';
import { startMock } from './mock.ts';

const out = join(here, 'logs', 'b7-summary.txt');
writeFileSync(out, '');
const say = (...a: unknown[]) => { const line = a.map((x) => (typeof x === 'string' ? x : JSON.stringify(x))).join(' '); console.log(line); appendFileSync(out, line + '\n'); };
const uid = Math.random().toString(36).slice(2, 8);
const folder = join(here, `scratch-${uid}`);
mkdirSync(folder);
const real = realpathSync(folder);
const outTmp = `/tmp/cdxb-out-${uid}`;
const probes = [
  { id: 'a.txt in the folder', cmd: 'printf hi > a.txt', check: join(real, 'a.txt') },
  { id: 'b.txt in a new folder under /tmp', cmd: `mkdir -p ${outTmp}/new && printf hi > ${outTmp}/new/b.txt`, check: `${outTmp}/new/b.txt` },
  { id: 'file under $TMPDIR (mktemp -d)', cmd: 'd=$(mktemp -d) && printf hi > $d/c.txt && echo wrote-ok && rm -rf $d' },
];
try {
  for (const [sandbox, policy] of [['workspace-write', 'on-request'], ['read-only', 'on-request']] as const) {
    const mock = await startMock();
    const app = new App(`b7-${sandbox}-${policy}`, real, mock.args);
    app.mocked = true;
    const asked: string[] = [];
    app.handler = (m) => { asked.push(m); return m.includes('requestApproval') ? { decision: 'decline' } : {}; };
    try {
      await app.init();
      const r = await app.request('thread/start', { cwd: real, approvalPolicy: policy, sandbox, model: 'mock-model' });
      for (const p of probes) {
        asked.length = 0; mock.state.requests.length = 0;
        mock.state.script = [{ call: 'exec_command', args: { cmd: p.cmd } }, { say: 'done' }];
        await app.turn(r.thread.id, p.id, {}, 60_000);
        say('ROW', { sandbox, policy, probe: p.id, asked: [...asked], onDisk: p.check ? existsSync(p.check) : null, modelSaw: mock.state.requests.at(-1)?.outputs.at(-1)?.replace(/\\n/g, ' ').replace(/\/var\/folders\/[^ ]*/g, '<TMPDIR>').slice(0, 220) });
      }
    } finally { await app.close(); await mock.close(); rmSync(join(real, 'a.txt'), { force: true }); }
  }
} finally { rmSync(folder, { recursive: true, force: true }); rmSync(outTmp, { recursive: true, force: true }); }
