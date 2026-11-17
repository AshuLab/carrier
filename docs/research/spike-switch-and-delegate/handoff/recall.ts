// node recall.ts <receiver claude|codex> <seed json in data/> <1|2> [control]
// A NEW conversation of the receiver in a new folder, with the history tool injected: handoff + first question, then six recall questions as separate turns.
// With `control`: a fresh conversation, no handoff and no tool, the same six questions in one turn.
import { rmSync } from 'node:fs';
import { SET1, SET2 } from './facts.ts';
import { buildHandoff, load, openLive, save, startHistoryServer, tmpFolder, turnsUsed, type Harness, type Item } from './lib.ts';

const receiver = process.argv[2] as Harness;
const seedFile = process.argv[3]!;
const set = process.argv[4] === '2' ? SET2 : SET1;
const control = process.argv[5] === 'control';
const items = load<Item[]>(seedFile);
const variant = process.env.VARIANT ?? 'a'; // a: first question asks for a status, order A B F C G D; b: first message only asks for OK, order C D B A F G
const order = (variant === 'b' ? ['C', 'D', 'B', 'A', 'F', 'G'] : ['A', 'B', 'F', 'C', 'G', 'D']).map((k) => set.questions.find((q) => q.key === k)!);
const judge = (said: string, q: (typeof order)[number]) => q.right.every((r) => r.test(said));
const folder = tmpFolder(`recv-${receiver}`);
const out: Record<string, unknown> = { receiver, seedFile, control, receiverModel: receiver === 'claude' ? 'haiku' : 'gpt-6-luna' };

if (control) {
  const live = await openLive(receiver, { folder });
  try {
    const text = 'Answer these six questions, one short numbered line each (1 to 6).\n' + order.map((q, i) => `${i + 1}. ${q.ask}`).join('\n');
    const r = await live.turn(text, undefined, `control ${receiver} ${set.id}`);
    out.said = r.said;
    out.tools = r.tools;
    out.perQuestion = order.map((q, i) => ({ key: q.key, where: q.where, right: judge(r.said.split('\n').find((l) => l.trim().startsWith(`${i + 1}.`)) ?? '', q) }));
    console.log(r.said, '\n', JSON.stringify(out.perQuestion));
  } finally {
    await live.close();
    rmSync(folder, { recursive: true, force: true });
  }
  save(`recall-control-${receiver}-${set.id}.json`, out);
  process.exit(0);
}

const handoff = buildHandoff(items);
const { mcp, server, counter } = await startHistoryServer(items);
const live = await openLive(receiver, { folder, mcp });
try {
  out.mcpProblem = live.conv.mcpProblem ?? null;
  out.handoff = { textBytes: handoff.textBytes, messageBytes: handoff.messageBytes, included: handoff.included, cut: handoff.cut ?? null, omitted: handoff.omitted };
  out.transcript = { jsonBytes: Buffer.byteLength(JSON.stringify(items)), textBytes: items.filter((i) => i.kind === 'user' || i.kind === 'assistant').reduce((n, i) => n + Buffer.byteLength((i as { text: string }).text), 0), items: items.length };
  console.log('mcpProblem', out.mcpProblem, JSON.stringify(out.handoff));
  const turns: unknown[] = [];
  const first = await live.turn(handoff.text + (variant === 'b' ? '\nReply with just: OK' : '\nIn one short sentence: what is this project, and what is its next step?'), undefined, `recv ${receiver} first`);
  turns.push({ q: 'first', serverArgs: counter.calls.map((c) => c.args), said: first.said, historyCalls: first.tools.filter((t) => t.endsWith('history')).length, tools: first.tools, outcome: first.outcome, errors: first.errors });
  console.log('first', first.outcome, first.tools, first.said.slice(0, 200));
  const rows: unknown[] = [];
  for (const q of order) {
    const before = counter.calls.length;
    const r = await live.turn(`${q.ask} Answer in one short sentence.`, undefined, `recv ${receiver} ${q.key}`);
    const calls = r.tools.filter((t) => t.endsWith('history')).length;
    const row = { key: q.key, where: q.where, source: q.source, right: judge(r.said, q), historyToolStarts: calls, serverCalls: counter.calls.length - before, serverArgs: counter.calls.slice(before).map((c) => c.args), said: r.said, outcome: r.outcome, errors: r.errors, otherTools: r.tools.filter((t) => !t.endsWith('history')) };
    rows.push(row);
    console.log(q.key, q.where, 'right=', row.right, 'history=', calls, 'server=', row.serverCalls, '|', r.said.replace(/\s+/g, ' ').slice(0, 160));
  }
  out.first = turns[0];
  out.rows = rows;
  out.totalServerCalls = counter.calls.length;
  out.score = { included: (rows as { where: string; right: boolean }[]).filter((r) => r.where === 'included' && r.right).length, omitted: (rows as { where: string; right: boolean }[]).filter((r) => r.where === 'omitted' && r.right).length };
  out.itemsAfter = live.items.length;
  console.log('score', JSON.stringify(out.score), 'turns used', turnsUsed());
} finally {
  await live.close();
  await server.close();
  rmSync(folder, { recursive: true, force: true });
  save(`recall-${receiver}-${set.id}${seedFile.includes('codex') ? '-from-codex' : '-from-claude'}-${variant}.json`, out);
}
