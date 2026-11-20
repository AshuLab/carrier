import { expect, test } from 'vitest';
import { childOptions, delegationRefusal, levelOf, type Level } from './levels.ts';

const claude = (permissionMode: string) => ({ permissionMode });
const codex = (sandbox: string, approvalPolicy?: string) => ({ sandbox, ...(approvalPolicy && { approvalPolicy }) });

test('Claude: dontAsk and plan are 0, default 1, acceptEdits 2, auto 3, and anything else is off the scale', () => {
  expect(levelOf('claude', claude('dontAsk'))).toBe(0);
  expect(levelOf('claude', claude('plan'))).toBe(0);
  expect(levelOf('claude', claude('default'))).toBe(1);
  expect(levelOf('claude', claude('acceptEdits'))).toBe(2);
  expect(levelOf('claude', claude('auto'))).toBe(3);
  for (const mode of ['bypassPermissions', '']) expect(levelOf('claude', claude(mode))).toBeUndefined();
});

test('Codex: read-only is 0 whatever the policy, workspace-write is 1 with untrusted and 2 with on-request or never, none is 3, and any other sandbox is off the scale', () => {
  for (const policy of ['untrusted', 'on-request', 'never', undefined]) expect(levelOf('codex', codex('read-only', policy))).toBe(0);
  expect(levelOf('codex', codex('workspace-write', 'untrusted'))).toBe(1);
  expect(levelOf('codex', codex('workspace-write', 'on-request'))).toBe(2);
  expect(levelOf('codex', codex('workspace-write', 'never'))).toBe(2);
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

test('a Codex agent configured with never under a level 2 parent keeps its options at 2, and an agent that is off the scale gets the parent\'s level', () => {
  expect(childOptions('codex', codex('workspace-write', 'never'), 2)).toEqual({ options: codex('workspace-write', 'never'), level: 2, lowered: false });
  for (const parent of [0, 1, 2, 3] as Level[]) {
    expect(childOptions('claude', claude('bypassPermissions'), parent)).toEqual({ options: { permissionMode: ['dontAsk', 'default', 'acceptEdits', 'auto'][parent] }, level: parent, lowered: true });
  }
});

test('a parent in auto has a Claude child in auto and a Codex child at 2, and a parent at 0 has a child that only reads', () => {
  expect(childOptions('claude', claude('auto'), 3)).toEqual({ options: claude('auto'), level: 3, lowered: false });
  expect(childOptions('claude', claude('acceptEdits'), 3)).toEqual({ options: claude('acceptEdits'), level: 2, lowered: false });
  expect(childOptions('claude', {}, 3)).toEqual({ options: claude('default'), level: 1, lowered: false });
  expect(childOptions('codex', codex('workspace-write', 'on-request'), 3)).toEqual({ options: codex('workspace-write', 'on-request'), level: 2, lowered: false });
  expect(childOptions('codex', codex('danger-full-access', 'never'), 3)).toEqual({ options: codex('workspace-write', 'on-request'), level: 2, lowered: true });
  expect(childOptions('claude', claude('auto'), 2)).toEqual({ options: claude('acceptEdits'), level: 2, lowered: true });
  expect(childOptions('claude', claude('plan'), 3)).toEqual({ options: claude('plan'), level: 0, lowered: false });
  for (const own of [claude('auto'), claude('acceptEdits'), codex('workspace-write', 'never'), {}]) expect(levelOf('claude', childOptions('claude', own, 0).options)).toBe(0);
  expect(childOptions('codex', codex('workspace-write', 'never'), 0)).toEqual({ options: codex('read-only', 'untrusted'), level: 0, lowered: true });
});

test('an agent with no options is taken at the adapter\'s defaults, and lowered only when they are above the parent', () => {
  expect(childOptions('claude', {}, 2)).toEqual({ options: claude('default'), level: 1, lowered: false });
  expect(childOptions('codex', {}, 1)).toEqual({ options: codex('workspace-write', 'untrusted'), level: 1, lowered: false });
  expect(childOptions('claude', {}, 0)).toEqual({ options: claude('dontAsk'), level: 0, lowered: true });
  expect(childOptions('codex', {}, 0)).toEqual({ options: codex('read-only', 'untrusted'), level: 0, lowered: true });
});

test('a child is never above its parent or its own agent, across both harnesses and every pair of levels', () => {
  const agentOptions = { claude: [claude('dontAsk'), claude('default'), claude('acceptEdits'), claude('plan'), claude('auto'), claude('bypassPermissions'), {}], codex: [codex('read-only', 'never'), codex('workspace-write', 'untrusted'), codex('workspace-write', 'on-request'), codex('workspace-write', 'never'), codex('danger-full-access', 'never'), {}] };
  for (const harness of ['claude', 'codex'] as const) {
    for (const own of agentOptions[harness]) {
      for (const parent of [0, 1, 2, 3] as Level[]) {
        const child = childOptions(harness, own, parent);
        expect(child.level).toBeLessThanOrEqual(parent);
        expect(child.level).toBe(Math.min(parent, harness === 'codex' ? 2 : 3, ...(levelOf(harness, own) === undefined ? [] : [levelOf(harness, own)!])));
        expect(levelOf(harness, child.options)).toBe(child.level);
        expect(child.lowered).toBe(levelOf(harness, own) === undefined || levelOf(harness, own)! > parent);
      }
    }
  }
});

test('delegation is refused only for what the mechanism cannot do: options off the scale, another harness, a Codex app-server that is unknown or older than the floor', () => {
  for (const permissionMode of ['dontAsk', 'plan', 'default', 'acceptEdits', 'auto']) expect(delegationRefusal('claude', claude(permissionMode)), permissionMode).toBeUndefined();
  for (const approvalPolicy of ['untrusted', 'on-request', 'never']) expect(delegationRefusal('codex', codex('workspace-write', approvalPolicy), '0.122.0'), approvalPolicy).toBeUndefined();
  expect(delegationRefusal('codex', codex('read-only', 'never'), '0.130.0')).toBeUndefined();
  expect(delegationRefusal('claude', claude('bypassPermissions'))).toMatch(/off the permission scale/);
  expect(delegationRefusal('codex', codex('danger-full-access', 'on-request'), '0.130.0')).toMatch(/off the permission scale/);
  expect(delegationRefusal('gemini', {})).toBe('A gemini session cannot delegate');
  expect(delegationRefusal('codex', {})).toMatch(/not known/);
  expect(delegationRefusal('codex', {}, '0.121.9')).toMatch(/older than 0.122.0/);
});
