// A3: opening with a model, through Carrier's real adapter (src/chat/claude.ts, imported not copied).
import { rmSync } from 'node:fs';
import { claudeChatRunner } from '../../../../src/chat/claude.ts';
import { save, tmp } from './lib.ts';
import type { ChatEvent } from '../../../../src/chat/runner.ts';

const cases: { name: string; options: Record<string, string> }[] = [
  { name: 'haiku', options: { model: 'haiku' } },
  { name: 'invalid', options: { model: 'not-a-real-model-xyz' } },
  { name: 'nothing', options: {} },
];
const out: unknown[] = [];
for (const c of cases) {
  const folder = tmp('cl-a3-');
  const t0 = Date.now();
  const rec: Record<string, unknown> = { case: c.name, options: c.options };
  try {
    const conv = await claudeChatRunner().open({ folder, options: c.options, env: process.env });
    rec.openToReadyMs = Date.now() - t0;
    const model = conv.options.find((o) => o.id === 'model');
    rec.current = model?.current;
    rec.listed = model?.values.map((v) => ({ id: v.id, label: v.label, version: (v as { version?: string }).version }));
    rec.optionIds = conv.options.map((o) => o.id);
    if (c.name === 'invalid') {
      const events: (ChatEvent & { at?: number })[] = [];
      const start = Date.now();
      conv.onEvent((e) => events.push({ ...e, at: Date.now() - start }));
      conv.send('Reply with just: OK');
      for (let i = 0; i < 600 && !events.some((e) => e.kind === 'turn_end'); i++) await new Promise((r) => setTimeout(r, 200));
      rec.turnEvents = events.map((e) => (e.kind === 'delta' ? { kind: 'delta', at: e.at } : e));
      rec.afterTurnCurrent = conv.options.find((o) => o.id === 'model')?.current;
    }
    await conv.close();
  } catch (e) {
    rec.openToFailMs = Date.now() - t0;
    rec.openThrew = `${(e as Error).name}: ${(e as Error).message}`;
  }
  console.log(JSON.stringify(rec));
  out.push(rec);
  rmSync(folder, { recursive: true, force: true });
}
save('a3', out);
process.exit(0);
