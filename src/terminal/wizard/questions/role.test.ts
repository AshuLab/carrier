import { expect, test } from 'vitest';
import { roleSlots } from '../roles.ts';
import { fakeDeps, quietUi } from '../testing.ts';
import { askRole, type RoleContext } from './role.ts';

const context = (ui: RoleContext['ui']): RoleContext => ({
  ui,
  deps: fakeDeps().deps,
  flags: {},
  interactive: true,
  providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } },
  locals: {},
  forge: { agents: [{ name: 'artanis-agent' }, { name: 'tassadar-agent' }] },
  readForge: () => {},
  login: 'diego',
});

test('the table of slots has the six roles, in the order a person meets them', () => {
  expect(roleSlots).toEqual(['author', 'reviewer', 'reviewer-2', 'reviewer-3', 'reviewer-4', 'lead-reviewer']);
});

test('the block takes a slot and asks the same questions named for it: reviewer-2 is the "reviewer 2"', async () => {
  const { ui, asked } = quietUi();
  const { role } = await askRole(context(ui), 'reviewer-2');
  expect(asked).toEqual([
    'GitHub profile for the reviewer 2',
    'Which account runs the reviewer 2?',
    'Model and effort: sonnet at high, change them?',
    "Customise the reviewer 2's persona?",
    'Turn failover on for the reviewer 2? When it runs out of credits it moves to the steps you list, each an account and a model.',
  ]);
  expect(role).toEqual({ identity: { kind: 'forge', agent: 'artanis-agent' }, provider: 'claude', model: 'sonnet', effort: 'high' });
});

test('the same block serves the lead reviewer and asks the same five questions', async () => {
  const { ui, asked } = quietUi();
  await askRole(context(ui), 'lead-reviewer');
  expect(asked.map((m) => m.replace('lead reviewer', 'ROLE'))).toEqual([
    'GitHub profile for the ROLE',
    'Which account runs the ROLE?',
    'Model and effort: sonnet at high, change them?',
    "Customise the ROLE's persona?",
    'Turn failover on for the ROLE? When it runs out of credits it moves to the steps you list, each an account and a model.',
  ]);
});
