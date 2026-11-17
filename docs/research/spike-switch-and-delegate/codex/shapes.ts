import { App, tmp } from './lib.ts';
import { startMock } from './mock.ts';
import { rmSync } from 'node:fs';
const folder = tmp('cdxb-');
const mock = await startMock();
const app = new App('shapes', folder, mock.args);
app.mocked = true;
try {
  await app.init();
  const r = await app.request('thread/start', { cwd: folder, approvalPolicy: 'never', sandbox: 'read-only', model: 'mock-model' });
  mock.state.script = [{ say: 'x' }];
  await app.turn(r.thread.id, 'hi', {}, 30_000);
  const ex = mock.state.toolDefs.find((t: any) => t.name === 'exec_command');
  console.log(JSON.stringify(ex).slice(0, 1500));
  const ns = mock.state.toolDefs.find((t: any) => t.type === 'namespace');
  console.log(JSON.stringify(ns).slice(0, 600));
} finally { await app.close(); await mock.close(); rmSync(folder, { recursive: true, force: true }); }
