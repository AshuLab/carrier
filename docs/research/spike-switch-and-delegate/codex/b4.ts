// B4: model/list timing, a thread with a valid model and with an invalid one.
import { App, tmp, itemsOf, turnsUsed } from './lib.ts';
import { rmSync } from 'node:fs';

const folder = tmp('cdxb-');
const app = new App('b4', folder);
try {
  const t0 = Date.now();
  const hello = await app.init();
  console.log('initialize ms', Date.now() - t0, 'userAgent', String(hello.userAgent).replace(/\(.*$/, ''));
  const t1 = Date.now();
  const list = await app.request('model/list', {});
  console.log('model/list ms', Date.now() - t1);
  console.log(list.data.map((m: any) => ({ model: m.model, hidden: m.hidden, isDefault: m.isDefault, efforts: m.supportedReasoningEfforts.map((e: any) => e.reasoningEffort), def: m.defaultReasoningEffort })));
  const t2 = Date.now();
  const all = await app.request('model/list', { includeHidden: true });
  console.log('model/list includeHidden ms', Date.now() - t2, 'count', all.data.length, 'next', all.nextCursor);

  // the invalid model: thread/start
  const sandbox = 'read-only';
  for (const model of [process.argv[2]!, 'no-such-model-xyz']) {
    const t = Date.now();
    try {
      const r = await app.request('thread/start', { cwd: folder, approvalPolicy: 'never', sandbox, model });
      console.log(`thread/start model=${model}: OK in ${Date.now() - t}ms, thread.model=${r.model}, id ${r.thread.id}`);
      if (process.argv[3] === 'turn') {
        const { completed, notes } = await app.turn(r.thread.id, 'Reply with just: OK', { effort: 'low' });
        console.log('  turn status', completed.turn.status, 'error', JSON.stringify(completed.turn.error ?? null), itemsOf(notes));
        console.log('  notes', [...new Set(notes.map((n) => n.method))].join(','));
        const err = notes.find((n) => n.method === 'error');
        if (err) console.log('  error note', JSON.stringify(err.params));
      }
    } catch (e) {
      console.log(`thread/start model=${model}: FAILED in ${Date.now() - t}ms`, (e as Error).message.slice(0, 300));
    }
  }
} finally {
  await app.close();
  rmSync(folder, { recursive: true, force: true });
  console.log('turns used', turnsUsed());
}
