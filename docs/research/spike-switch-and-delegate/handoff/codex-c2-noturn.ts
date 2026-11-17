// No model turn at all (Codex is at its usage limit): what the app-server protocol accepts for a handoff and how it lists a skill.
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { realCodexDeps } from '../../../../src/chat/codex.ts';
import { endGroup } from '../../../../src/chat/group.ts';
import { buildHandoff, load, save, tmpFolder, type Item } from './lib.ts';

const folder = tmpFolder('c2-codex');
for (const dir of ['.agents/skills/pong', '.codex/skills/pong']) {
  mkdirSync(join(folder, dir), { recursive: true });
  writeFileSync(join(folder, dir, 'SKILL.md'), '---\nname: pong\ndescription: Answers PONG followed by the argument\n---\nReply with exactly the text PONG: followed by the argument the user gave, and nothing else.\n');
}
const small = buildHandoff(load<Item[]>('seed-quillfinch-claude.json').filter((i) => i.position <= 5)).text;
const binary = realCodexDeps.resolve(undefined, process.env);
const transport = realCodexDeps.spawn(binary, { cwd: folder, env: process.env, args: [] });
const replies = new Map<number, any>();
transport.onLine((line) => {
  const m = JSON.parse(line);
  if (typeof m.id === 'number' && m.method === undefined) replies.set(m.id, m);
});
let n = 0;
const call = async (method: string, params: unknown) => {
  const id = ++n;
  transport.write(JSON.stringify({ id, method, params }));
  for (let i = 0; i < 300 && !replies.has(id); i++) await new Promise((r) => setTimeout(r, 100));
  return replies.get(id) ?? { timeout: true };
};
const out: Record<string, unknown> = {};
try {
  const hello = await call('initialize', { clientInfo: { name: 'carrier', title: 'Carrier', version: '0.0.0' } });
  out.initialize = { userAgentVersion: /\/(\d+\.\d+\.\d+)/.exec(String(hello.result?.userAgent))?.[1] };
  transport.write(JSON.stringify({ method: 'initialized' }));
  const skills = await call('skills/list', { cwds: [folder], forceReload: true });
  out.skills = (skills.result?.data ?? []).flatMap((e: any) => (e.skills ?? []).filter((s: any) => s.name === 'pong').map((s: any) => ({ name: s.name, path: s.path.replace(folder, '<folder>'), scope: s.scope, enabled: s.enabled }))).concat(skills.error ? [{ error: skills.error.message }] : []);
  out.skillsErrors = (skills.result?.data ?? []).flatMap((e: any) => e.errors ?? []);
  const started = await call('thread/start', { cwd: folder, approvalPolicy: 'never', sandbox: 'read-only', model: 'gpt-6-luna', developerInstructions: small });
  out.threadStartWithDeveloperInstructions = started.error ? { error: started.error.message } : { ok: true, responseKeys: Object.keys(started.result), instructionSources: (started.result.instructionSources ?? []).length };
  const threadId = started.result?.thread?.id;
  if (threadId) {
    const injected = await call('thread/inject_items', { threadId, items: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: small.slice(0, 300) }] }] });
    out.injectItems = injected.error ? { error: injected.error.message } : { ok: true, result: injected.result };
    const baseline = await call('thread/start', { cwd: folder, approvalPolicy: 'never', sandbox: 'read-only', model: 'gpt-6-luna', baseInstructions: 'x'.repeat(10) });
    out.threadStartWithBaseInstructionsAccepted = baseline.error ? { error: baseline.error.message } : { ok: true };
  }
  console.log(JSON.stringify(out, null, 1));
} finally {
  if (transport.pid !== undefined) await endGroup(transport.pid);
  save('c2-codex-noturn.json', out);
  rmSync(folder, { recursive: true, force: true });
}
