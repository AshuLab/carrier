// Follow-ups for plan mode, which behaved differently from the others.
import { join } from 'node:path';
import { existsSync, rmSync, writeFileSync } from 'node:fs';
import { open, save, state, tmp, toyMcp } from './lib.ts';
const PROMPT = 'Call ping_read, then call ping_act, then say what happened';
const READ = 'mcp__carrier-chat__ping_read';
const mcp = await toyMcp();
const out: Record<string, unknown> = {};
const brief = (t: any) => ({ outcome: t.outcome, tools: t.tools.map((x: any) => x.name), asked: t.asked.map((a: any) => ({ tool: a.tool, reason: a.decisionReason, title: a.title, input: a.input })), results: t.results.map((r: any) => `${r.error ? 'ERR ' : 'ok '}${r.text.slice(0, 120)}`), said: t.said.slice(0, 300) });
for (const [name, allowedTools, allow] of [['plan-allow-read-in-callback', [READ], [READ]], ['plan-wildcard-deny-all', ['mcp__carrier-chat__*'], undefined]] as const) {
  const folder = tmp('cl-a4-');
  state.log = join(folder, '..', `${name}-${process.pid}.log`); writeFileSync(state.log, '');
  const c = await open({ folder, mode: 'plan', model: 'haiku', allowedTools: [...allowedTools], allow: allow && [...allow], mcp });
  const turn = await c.send(PROMPT);
  const log = (await import('node:fs')).readFileSync(state.log, 'utf8').trim().split('\n').filter(Boolean);
  out[name] = { ...brief(turn), serverLog: log };
  console.log(name, JSON.stringify(out[name]));
  await c.close(); rmSync(folder, { recursive: true, force: true }); rmSync(state.log, { force: true });
}
await mcp.close();
{
  const work = tmp('cl-a4w-'); const outside = tmp('cl-a4o-');
  const c = await open({ folder: work, mode: 'plan', model: 'haiku' });
  const NOPE = ' Do nothing else, and if it is refused do not try another way.';
  const t1 = await c.send(`Create a file named b.txt with the text hi inside, in the folder ${outside}.${NOPE}`);
  const t2 = await c.send(`Run the shell command: curl -sI https://example.com | head -1${NOPE}`);
  out['plan-fresh-probes'] = { write_outside: { ...brief(t1), fileExists: existsSync(join(outside, 'b.txt')) }, curl: brief(t2) };
  console.log('plan-fresh-probes', JSON.stringify(out['plan-fresh-probes']));
  await c.close(); rmSync(work, { recursive: true, force: true }); rmSync(outside, { recursive: true, force: true });
}
save('a4-plan-followups', out);
process.exit(0);
