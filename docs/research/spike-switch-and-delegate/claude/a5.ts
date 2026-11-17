// Last two turns: a shell write in plan mode, and the Write tool in dontAsk mode.
import { join } from 'node:path';
import { existsSync, rmSync } from 'node:fs';
import { open, save, tmp } from './lib.ts';
const NOPE = ' Do nothing else, and if it is refused do not try another way.';
const brief = (t: any) => ({ outcome: t.outcome, tools: t.tools.map((x: any) => `${x.name} ${JSON.stringify(x.input).slice(0, 100)}`), asked: t.asked.map((a: any) => ({ tool: a.tool, reason: a.decisionReason, input: a.input })), results: t.results.map((r: any) => `${r.error ? 'ERR ' : 'ok '}${r.text.slice(0, 160)}`), said: t.said.slice(0, 200) });
const out: Record<string, unknown> = {};
for (const [mode, prompt, file] of [['plan', `Run the shell command: touch c.txt${NOPE}`, 'c.txt'], ['dontAsk', `Use the Write tool to create a file named d.txt with the text hi inside, in the current working folder.${NOPE}`, 'd.txt']] as const) {
  const work = tmp('cl-a5-');
  const c = await open({ folder: work, mode, model: 'haiku' });
  const t = await c.send(prompt);
  out[mode] = { ...brief(t), fileExists: existsSync(join(work, file)) };
  console.log(mode, JSON.stringify(out[mode]));
  await c.close(); rmSync(work, { recursive: true, force: true });
}
save('a5-last-two', out);
process.exit(0);
