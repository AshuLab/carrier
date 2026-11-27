import { expect, test } from 'vitest';
import { journaled } from '../../prompts/journal.ts';
import { Back } from '../../prompts/types.ts';
import { roleSlots } from '../roles.ts';
import { fakeDeps, quietUi } from '../testing.ts';
import { askRole, type RoleContext } from './role.ts';

const context = (ui: RoleContext['ui']): RoleContext => ({
  ui,
  deps: fakeDeps().deps,
  flags: {},
  interactive: true,
  unattended: false,
  providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } },
  locals: {},
  forge: { agents: [{ name: 'artanis-agent' }, { name: 'tassadar-agent' }] },
  readForge: () => {},
  login: 'diego',
  said: { failover: false },
});

test('the table of slots has the three roles that have flags, in the order a person meets them', () => {
  expect(roleSlots).toEqual(['author', 'reviewer', 'lead-reviewer']);
});

test('the block of an extra reviewer asks the same questions, calling it the "extra reviewer" and never by its name or place', async () => {
  const { ui, asked } = quietUi();
  const { role } = await askRole(context(ui), 'extra-reviewer');
  expect(asked).toEqual([
    'GitHub profile for the extra reviewer',
    'Which account runs the extra reviewer?',
    'Model and effort: sonnet at high, change them?',
    "Customise the extra reviewer's persona?",
    'Turn failover on for the extra reviewer? When it runs out of credits it moves to the steps you list, each an account and a model.',
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

test('the journal serves a block of any slot: an extra reviewer goes back one question and asks only that one again, with no per-role code', async () => {
  const { ui, asked } = quietUi({ 'Which account runs the extra reviewer?': 'codex' });
  let thrown = false;
  const spy: RoleContext['ui'] = {
    ...ui,
    confirm: async (m, i) => {
      if (m === "Customise the extra reviewer's persona?" && !thrown) ((thrown = true), (() => { throw new Back(); })());
      return ui.confirm(m, i);
    },
  };
  const journal = journaled(spy);
  const block = () => {
    journal.at('extra-reviewer');
    return askRole(context(journal.ui), 'extra-reviewer');
  };
  const done = await block().catch((error) => {
    expect(error).toBeInstanceOf(Back);
    expect(journal.back()).toBe('question'); // drops the model question's answer
    return block();
  });
  expect(asked).toEqual([
    'GitHub profile for the extra reviewer',
    'Which account runs the extra reviewer?',
    'Model and effort: gpt-test at high, change them?',
    'Model and effort: gpt-test at high, change them?', // the only one shown again: Esc at the persona went back to it, not to the profile or the account
    "Customise the extra reviewer's persona?",
    'Turn failover on for the extra reviewer? When it runs out of credits it moves to the steps you list, each an account and a model.',
  ]);
  expect(done.role.provider).toBe('codex');
});
