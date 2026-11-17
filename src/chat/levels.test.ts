import { expect, test } from 'vitest';
import { childOptions, levelOf, type Level } from './levels.ts';

const claude = (permissionMode: string) => ({ permissionMode });
const codex = (sandbox: string, approvalPolicy?: string) => ({ sandbox, ...(approvalPolicy && { approvalPolicy }) });

test('Claude: dontAsk is 0, default 1, acceptEdits 2, and plan, auto and anything else are off the scale', () => {
  expect(levelOf('claude', claude('dontAsk'))).toBe(0);
  expect(levelOf('claude', claude('default'))).toBe(1);
  expect(levelOf('claude', claude('acceptEdits'))).toBe(2);
  for (const mode of ['plan', 'auto', 'bypassPermissions', '']) expect(levelOf('claude', claude(mode))).toBeUndefined();
});

test('Codex: read-only is 0 whatever the policy, workspace-write is 1 with untrusted and 2 with on-request, and never or any other sandbox is off the scale', () => {
  for (const policy of ['untrusted', 'on-request', 'never', undefined]) expect(levelOf('codex', codex('read-only', policy))).toBe(0);
  expect(levelOf('codex', codex('workspace-write', 'untrusted'))).toBe(1);
  expect(levelOf('codex', codex('workspace-write', 'on-request'))).toBe(2);
  expect(levelOf('codex', codex('workspace-write', 'never'))).toBeUndefined();
  expect(levelOf('codex', codex('danger-full-access', 'untrusted'))).toBeUndefined();
});

test('options that are not set are the adapter\'s defaults, and options of other kinds do not count', () => {
  expect(levelOf('claude', {})).toBe(1);
  expect(levelOf('codex', {})).toBe(1);
  expect(levelOf('codex', { sandbox: 'workspace-write' })).toBe(1);
  expect(levelOf('codex', { approvalPolicy: 'on-request' })).toBe(2);
  expect(levelOf('claude', { model: 'opus', effort: 'high' })).toBe(1);
  expect(levelOf('claude', { model: 'opus', permissionMode: 'acceptEdits' })).toBe(2);
});

test('a level 2 agent under a level 1 parent runs at 1 and is lowered, to the options of its own harness', () => {
  expect(childOptions('claude', { ...claude('acceptEdits'), model: 'opus' }, 1)).toEqual({ options: { model: 'opus', permissionMode: 'default' }, level: 1, lowered: true });
  expect(childOptions('codex', codex('workspace-write', 'on-request'), 1)).toEqual({ options: codex('workspace-write', 'untrusted'), level: 1, lowered: true });
});

test('a level 0 agent under a level 2 parent stays at 0 and is not lowered', () => {
  expect(childOptions('claude', claude('dontAsk'), 2)).toEqual({ options: claude('dontAsk'), level: 0, lowered: false });
  expect(childOptions('codex', codex('read-only', 'on-request'), 2)).toEqual({ options: codex('read-only', 'on-request'), level: 0, lowered: false });
});

test('a Codex agent configured with never under a level 2 parent runs at 2, and an off-scale Claude agent never gets plan or auto', () => {
  expect(childOptions('codex', codex('workspace-write', 'never'), 2)).toEqual({ options: codex('workspace-write', 'on-request'), level: 2, lowered: true });
  for (const parent of [0, 1, 2] as Level[]) {
    const child = childOptions('claude', claude('plan'), parent);
    expect(child).toMatchObject({ level: parent, lowered: true });
    expect(levelOf('claude', child.options)).toBe(parent);
  }
});

test('an agent with no options is taken at the adapter\'s defaults, and lowered only when they are above the parent', () => {
  expect(childOptions('claude', {}, 2)).toEqual({ options: claude('default'), level: 1, lowered: false });
  expect(childOptions('codex', {}, 1)).toEqual({ options: codex('workspace-write', 'untrusted'), level: 1, lowered: false });
  expect(childOptions('claude', {}, 0)).toEqual({ options: claude('dontAsk'), level: 0, lowered: true });
  expect(childOptions('codex', {}, 0)).toEqual({ options: codex('read-only', 'untrusted'), level: 0, lowered: true });
});

test('a child is never above its parent or its own agent, across both harnesses and every pair of levels', () => {
  const agentOptions = { claude: [claude('dontAsk'), claude('default'), claude('acceptEdits'), claude('plan'), claude('auto'), {}], codex: [codex('read-only', 'never'), codex('workspace-write', 'untrusted'), codex('workspace-write', 'on-request'), codex('workspace-write', 'never'), {}] };
  for (const harness of ['claude', 'codex'] as const) {
    for (const own of agentOptions[harness]) {
      for (const parent of [0, 1, 2] as Level[]) {
        const child = childOptions(harness, own, parent);
        expect(child.level).toBeLessThanOrEqual(parent);
        expect(levelOf(harness, child.options)).toBe(child.level);
        expect(child.lowered).toBe(levelOf(harness, own) === undefined || levelOf(harness, own)! > parent);
      }
    }
  }
});
