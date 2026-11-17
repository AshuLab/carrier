// node claude-c2.ts [list|base|a|b|c]: where the handoff can sit when the first message after a switch invokes a skill, Claude as the new agent.
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { claudeChatRunner, realClaudeDeps } from '../../../../src/chat/claude.ts';
import { buildHandoff, load, openLive, save, tmpFolder, turnsUsed, type Item } from './lib.ts';

const which = process.argv[2] ?? 'list';
const folder = tmpFolder('c2-claude');
mkdirSync(join(folder, '.claude/skills/pong'), { recursive: true });
writeFileSync(join(folder, '.claude/skills/pong/SKILL.md'), '---\nname: pong\ndescription: Answers PONG followed by the argument\nargument-hint: <word>\n---\nReply with exactly the text PONG:$ARGUMENTS and nothing else. Do not call any tool.\n');
// a small handoff: the first messages of the seed (the person, the agent, the decision)
const small = buildHandoff(load<Item[]>('seed-quillfinch-claude.json').filter((i) => i.position <= 5)).text;
const recall = 'Who is the project owner? Answer in one short sentence.';
const result: Record<string, unknown> = { which, handoffBytes: Buffer.byteLength(small) };
const show = (label: string, r: { said: string; tools: string[]; outcome: string; errors: string[]; events: unknown[] }) => {
  const line = { label, said: r.said.slice(0, 300), tools: r.tools, outcome: r.outcome, errors: r.errors };
  console.log(JSON.stringify(line));
  return line;
};
try {
  if (which === 'list') {
    const live = await openLive('claude', { folder });
    try {
      result.commands = live.conv.commands.filter((c) => c.name === 'pong').map((c) => ({ id: c.id, name: c.name, kind: c.kind, hint: c.argumentHint, description: c.description }));
      console.log(JSON.stringify(result.commands));
    } finally {
      await live.close();
    }
  } else if (which === 'base') {
    const live = await openLive('claude', { folder });
    try {
      const pong = live.conv.commands.find((c) => c.name === 'pong')!;
      result.base = show('base: /pong ALPHA through send(text, command)', await live.turn('ALPHA', pong, 'c2 claude base'));
      result.userEvent = live.items.find((i) => i.kind === 'user');
    } finally {
      await live.close();
    }
  } else if (which === 'a') {
    const live = await openLive('claude', { folder });
    try {
      result.first = show('a: handoff in front of the command message (plain send)', await live.turn(small + '\n/pong ALPHA', undefined, 'c2 claude a'));
      result.recall = show('a: recall', await live.turn(recall, undefined, 'c2 claude a recall'));
    } finally {
      await live.close();
    }
  } else if (which === 'b') {
    const live = await openLive('claude', { folder });
    try {
      const pong = live.conv.commands.find((c) => c.name === 'pong')!;
      result.carry = show('b: a turn of its own that carries the handoff', await live.turn(small + '\nThis is context only: reply with just OK.', undefined, 'c2 claude b carry'));
      result.first = show('b: the command', await live.turn('BETA', pong, 'c2 claude b cmd'));
      result.recall = show('b: recall', await live.turn(recall, undefined, 'c2 claude b recall'));
    } finally {
      await live.close();
    }
  } else if (which === 'c') {
    const runner = claudeChatRunner({ ...realClaudeDeps, query: (p) => realClaudeDeps.query({ ...p, options: { ...p.options, systemPrompt: { type: 'preset', preset: 'claude_code', append: small } } }) });
    const live = await openLive('claude', { folder, runner });
    try {
      const pong = live.conv.commands.find((c) => c.name === 'pong')!;
      result.first = show('c: handoff in systemPrompt append, then the command', await live.turn('GAMMA', pong, 'c2 claude c cmd'));
      result.recall = show('c: recall', await live.turn(recall, undefined, 'c2 claude c recall'));
    } finally {
      await live.close();
    }
  }
  console.log('turns used', turnsUsed());
} finally {
  save(`c2-claude-${which}.json`, result);
  rmSync(folder, { recursive: true, force: true });
}
