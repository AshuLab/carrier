// A1: one tool asks while the other is pre-approved, per permission mode, plus three controls.
import { mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { open, save, state, tmp, toyMcp } from './lib.ts';

const PROMPT = 'Call ping_read, then call ping_act, then say what happened';
const READ = 'mcp__carrier-chat__ping_read';
const ACT = 'mcp__carrier-chat__ping_act';
const only = process.argv.slice(2);

const runs: { name: string; mode: string; allowedTools: string[]; settings?: object }[] = [
  ...['default', 'acceptEdits', 'plan', 'auto', 'dontAsk'].map((mode) => ({ name: `mode-${mode}`, mode, allowedTools: [READ] })),
  { name: 'control-wildcard', mode: 'default', allowedTools: ['mcp__carrier-chat__*'] },
  { name: 'control-deny-rule-on-act', mode: 'default', allowedTools: ['mcp__carrier-chat__*'], settings: { permissions: { deny: [ACT] } } },
  { name: 'control-ask-rule-on-read', mode: 'default', allowedTools: [READ], settings: { permissions: { ask: [READ] } } },
];

const mcp = await toyMcp();
const all: unknown[] = [];
try {
  for (const r of runs) {
    if (only.length > 0 && !only.includes(r.name)) continue;
    const folder = tmp('cl-a1-');
    if (r.settings) { mkdirSync(join(folder, '.claude')); writeFileSync(join(folder, '.claude', 'settings.json'), JSON.stringify(r.settings)); }
    state.log = join(folder, '..', `${r.name}-${process.pid}.log`);
    writeFileSync(state.log, '');
    let rec: Record<string, unknown>;
    try {
      const c = await open({ folder, mode: r.mode, model: 'haiku', allowedTools: r.allowedTools, mcp });
      try {
        const turn = await c.send(PROMPT);
        const log = readFileSync(state.log, 'utf8').trim().split('\n').filter(Boolean);
        rec = { run: r.name, settings: r.settings, allowedTools: r.allowedTools, init: c.init, readyMs: c.readyMs, turn, serverLog: log,
          askedRead: turn.asked.some((a) => a.tool === READ), askedAct: turn.asked.some((a) => a.tool === ACT), actExecuted: log.includes('ping_act executed'), readExecuted: log.includes('ping_read executed') };
      } finally { await c.close(); }
    } catch (e) { rec = { run: r.name, error: String(e).slice(0, 400) }; }
    console.log(JSON.stringify({ ...rec, init: undefined, turn: rec.turn && { ...(rec.turn as object), asked: (rec.turn as any).asked.map((a: any) => ({ tool: a.tool, title: a.title, input: a.input })) } }));
    all.push(rec);
    save(`a1-${r.name}`, rec);
    rmSync(folder, { recursive: true, force: true });
    rmSync(state.log, { force: true });
  }
} finally { await mcp.close(); }
process.exit(0);
