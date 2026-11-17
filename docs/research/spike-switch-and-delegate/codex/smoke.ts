import { App, tmp, itemsOf } from './lib.ts';
import { startMock } from './mock.ts';
import { rmSync } from 'node:fs';
const folder = tmp('cdxb-');
const mock = await startMock();
const app = new App('smoke', folder, mock.args);
try {
  await app.init();
  app.handler = (m) => { throw new Error('unexpected ' + m); };
  const r = await app.request('thread/start', { cwd: folder, approvalPolicy: 'never', sandbox: 'read-only', model: 'mock-model' });
  console.log('thread', r.thread.id, r.model, r.modelProvider);
  mock.state.script = [{ say: 'hello from mock' }];
  const t = await app.turn(r.thread.id, 'hi', { effort: 'low' }, 30_000);
  console.log(t.completed.turn.status, JSON.stringify(t.completed.turn.error ?? null), itemsOf(t.notes));
  console.log(JSON.stringify(mock.state.requests, null, 1).slice(0, 3000));
} finally { await app.close(); await mock.close(); rmSync(folder, { recursive: true, force: true }); }
