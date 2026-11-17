// A2: what each mode lets the agent do without asking; four probes per mode, canUseTool records and denies everything.
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { open, save, tmp } from './lib.ts';

const modes = process.argv.slice(2).length > 0 ? process.argv.slice(2) : ['default', 'acceptEdits', 'plan', 'auto', 'dontAsk'];
const NOPE = ' Do nothing else, and if it is refused do not try another way.';
for (const mode of modes) {
  const work = tmp('cl-a2w-');
  const outside = tmp('cl-a2o-'); // a unique new folder under /tmp, outside the working folder
  const probes = [
    { id: 'write-inside', prompt: `Create a file named a.txt in the current working folder with the text hi inside.${NOPE}`, file: join(work, 'a.txt') },
    { id: 'write-outside', prompt: `Create a file named b.txt with the text hi inside, in the folder ${outside}.${NOPE}`, file: join(outside, 'b.txt') },
    { id: 'curl', prompt: `Run the shell command: curl -sI https://example.com | head -1${NOPE}` },
    { id: 'ls', prompt: `Run the shell command: ls${NOPE}` },
  ];
  let rec: Record<string, unknown>;
  try {
    const c = await open({ folder: work, mode, model: 'haiku' });
    try {
      const turns = [];
      for (const p of probes) {
        const turn = await c.send(p.prompt);
        turns.push({ probe: p.id, turn, fileExists: p.file ? existsSync(p.file) : undefined, fileText: p.file && existsSync(p.file) ? readFileSync(p.file, 'utf8').slice(0, 40) : undefined });
      }
      rec = { mode, init: c.init, turns };
    } finally { await c.close(); }
  } catch (e) { rec = { mode, error: String(e).slice(0, 400) }; }
  for (const t of (rec.turns ?? []) as any[]) console.log(JSON.stringify({ mode, probe: t.probe, outcome: t.turn.outcome, tools: t.turn.tools.map((x: any) => x.name), asked: t.turn.asked.map((a: any) => ({ tool: a.tool, title: a.title, reason: a.decisionReason, blocked: a.blockedPath, input: a.input })), results: t.turn.results.map((r: any) => `${r.error ? 'ERR ' : 'ok '}${r.text.slice(0, 100)}`), file: t.fileExists, said: t.turn.said.slice(0, 160) }));
  if (rec.error) console.log(JSON.stringify(rec));
  save(`a2-${mode}`, rec);
  rmSync(work, { recursive: true, force: true });
  rmSync(outside, { recursive: true, force: true });
}
process.exit(0);
