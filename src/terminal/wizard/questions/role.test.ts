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

test('in edit mode the block starts from the file: its model, effort and persona, and a failover it has is offered first', async () => {
  const { ui, asked } = quietUi({ 'Model and effort: opus at max, change them?': true, 'Model for the author': 'sonnet', "Customise the author's persona?": true });
  const seen: Record<string, unknown> = {};
  const spy: RoleContext['ui'] = {
    ...ui,
    select: async (o) => ((seen[o.message] = o.initialValue), ui.select(o)),
    text: async (o) => ((seen[o.message] = o.defaultValue), ui.text(o)),
    confirm: async (m, initial) => ((seen[m] = initial), ui.confirm(m, initial)),
  };
  const from = { identity: { kind: 'gh' as const }, provider: 'claude', model: 'opus', effort: 'max' as const, persona: { name: 'Rex', prompt: 'Be rigorous.' } };
  await askRole(context(spy), 'author', { from, steps: [{ provider: 'codex', model: 'gpt-test' }] });
  expect(asked).toContain('Model and effort: opus at max, change them?');
  expect(seen['Effort for the author']).toBe('max');
  expect(seen["Customise the author's persona?"]).toBe(true); // the file has one
  expect(seen['Author persona: give it a name']).toBe('Rex');
  expect(seen['Author persona: describe how it behaves']).toBe('Be rigorous.');
  expect(asked.some((m) => m.startsWith('Keep the failover you have? author: codex gpt-test'))).toBe(true);
  expect(asked.findIndex((m) => m.startsWith('Keep the failover'))).toBeGreaterThan(asked.indexOf("Customise the author's persona?"));
});
