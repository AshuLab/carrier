// node seed.ts <claude|codex> <1|2>: eight real turns with the person describing a project; saves the ChatEvents with their positions.
import { rmSync } from 'node:fs';
import { SET1, SET2, pasteText } from './facts.ts';
import { openLive, save, tmpFolder, turnsUsed, type Harness } from './lib.ts';

const harness = process.argv[2] as Harness;
const set = process.argv[3] === '2' ? SET2 : SET1;
const folder = tmpFolder(`seed-${harness}`);
const live = await openLive(harness, { folder });
try {
  for (const [i, t] of set.turns.entries()) {
    const text = t.paste ? pasteText(t.paste) : t.text!;
    const r = await live.turn(text, undefined, `seed ${harness} ${set.id} t${i + 1}`);
    console.log(`t${i + 1} [${r.outcome}] tools=${r.tools.length} denied=${r.approvalsDenied.length} said: ${r.said.replace(/\s+/g, ' ').slice(0, 110)}`);
    if (r.outcome !== 'ok') throw new Error('turn failed: ' + r.errors.join(' | '));
  }
  save(`seed-${set.id}-${harness}.json`, live.items);
  const size = JSON.stringify(live.items).length;
  const text = live.items.filter((i) => i.kind === 'user' || i.kind === 'assistant').reduce((n, i) => n + Buffer.byteLength((i as { text: string }).text), 0);
  console.log(`saved ${live.items.length} items; json bytes ${Buffer.byteLength(JSON.stringify(live.items))}; user+assistant text bytes ${text}; turns used so far ${turnsUsed()}`);
} finally {
  await live.close();
  rmSync(folder, { recursive: true, force: true });
}
