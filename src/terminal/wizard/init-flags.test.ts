import { join } from 'node:path';
import { expect, test } from 'vitest';
import type { InitDeps } from './deps.ts';
import type { InitFlags } from './flags.ts';
import { asFiles, fakeDeps, providersWritten, quietUi, useTempDir } from './testing.ts';
import { runInit } from './wizard.ts';

const dir = useTempDir();

/** Fake deps and a terminal that count every call that looks at the machine, GitHub or the person. */
function counted(over: Partial<InitDeps> = {}) {
  const calls: string[] = [];
  const spy = <F extends (...args: never[]) => unknown>(name: string, fn: F) => ((...args: never[]) => (calls.push(name), fn(...args))) as F;
  const { deps, written } = fakeDeps(over);
  const wrapped = Object.fromEntries(Object.entries(deps).map(([name, value]) => [name, typeof value === 'function' ? spy(name, value as never) : value])) as unknown as InitDeps;
  wrapped.machine = Object.fromEntries(Object.entries(deps.machine).map(([name, value]) => [name, spy(`machine.${name}`, value as never)])) as unknown as InitDeps['machine'];
  const { ui, asked, notes } = quietUi();
  const watched = { ...ui, busy: ((message, work) => (calls.push(`busy:${message}`), work())) as typeof ui.busy, intro: () => void calls.push('intro') };
  return { deps: wrapped, written, calls, ui: watched, asked, notes };
}

test.each([
  ['an effort that is not a level', { authorEffort: 'turbo' }, '--author-effort "turbo"'],
  ['the lead reviewer\'s effort that is not a level', { leadReviewerEffort: 'ultra' }, '--lead-reviewer-effort "ultra"'],
  ['an agent that is not <harness>:<model>', { reviewer: 'codex' }, '--reviewer: '],
  ['a profile that is neither forge:<agent> nor gh', { authorProfile: 'me' }, '--author-profile: '],
  ['a provider that is not a local server', { authorProvider: 'cloud' }, '--author-provider: '],
  ['a persona that is empty', { reviewerPersonaName: '' }, '--reviewer-persona-name: '],
  ['an orchestrator profile that is neither forge:<agent> nor gh', { orchestratorProfile: 'me' }, '--orchestrator-profile: '],
  ['a repo that is not owner/name', { repo: ['AshuLab'] }, '--repo "AshuLab": must be owner/name'],
  ['--yes with no --repo', { yes: true }, '--repo'],
  ['a malformed failover step', { authorFailover: ['codex:'] }, '--author-failover "codex:"'],
  ['a third failover step', { reviewerFailover: ['a', 'b', 'c'] }, '--reviewer-failover: at most 2 steps'],
  ['an extra reviewer flag that names no reviewer', { extraReviewerType: ['Ghost=ux'] }, '--extra-reviewer-type "Ghost=ux"'],
  ['a fourth extra reviewer', { extraReviewer: ['a=claude:m', 'b=claude:m', 'c=claude:m', 'd=claude:m'] }, '--extra-reviewer: at most 3'],
  ['an extra reviewer name given twice without regard to case', { extraReviewer: ['Seg=claude:m', 'seg=claude:m'] }, '--extra-reviewer "seg=claude:m"'],
  ['a blank extra reviewer name', { extraReviewer: [' =claude:m'] }, '--extra-reviewer " =claude:m"'],
  ['an extra reviewer name over 40 characters', { extraReviewer: [`${'a'.repeat(41)}=claude:m`] }, '--extra-reviewer'],
  ['an extra reviewer name with a line break', { extraReviewer: ['a\nb=claude:m'] }, '--extra-reviewer'],
  ['an extra reviewer flag value with no =', { extraReviewer: ['A=claude:m'], extraReviewerEffort: ['high'] }, '--extra-reviewer-effort "high"'],
  ['an extra reviewer type that is not a slug', { extraReviewer: ['A=claude:m'], extraReviewerType: ['A=Not A Slug'] }, '--extra-reviewer-type'],
  ['an extra reviewer effort that is not a level', { extraReviewer: ['A=claude:m'], extraReviewerEffort: ['A=turbo'] }, '--extra-reviewer-effort "turbo"'],
] as [string, InitFlags, string][])('%s is refused naming its flag before anything is probed, shown or written', async (_name, flags, expected) => {
  const { deps, written, calls, ui, asked, notes } = counted();
  await expect(runInit({ out: join(dir, 'never.json'), ...flags }, ui, deps)).rejects.toThrow(expected);
  expect(calls).toEqual([]); // no detection, no gh, no listing, no which, no forge registry, no question
  expect(asked).toEqual([]);
  expect(notes).toEqual([]);
  expect(written).toEqual({});
});

test('a failover account that does not exist is refused before the first question, once the accounts are known', async () => {
  const { deps, written, calls, ui, asked } = counted();
  await expect(runInit({ out: join(dir, 'ghost.json'), authorFailover: ['ghost:m'] }, ui, deps)).rejects.toThrow('--author-failover "ghost:m": there is no account named "ghost" (accounts: claude, codex)');
  expect(calls.some((call) => call.startsWith('machine.'))).toBe(true); // the accounts come from the machine
  expect(calls).not.toContain('listRepos'); // the repos are listed last
  expect(calls).not.toContain('forgeAgents');
  expect(asked).toEqual([]);
  expect(written).toEqual({});
});

test('an extra reviewer failover account that does not exist is refused before the first question, once the accounts are known', async () => {
  const { deps, written, calls, ui, asked } = counted();
  await expect(runInit({ out: join(dir, 'ghost-extra.json'), extraReviewer: ['Seg=claude:m'], extraReviewerFailover: ['Seg=ghost:m'] }, ui, deps)).rejects.toThrow('--extra-reviewer-failover "ghost:m": there is no account named "ghost" (accounts: claude, codex)');
  expect(calls).not.toContain('listRepos');
  expect(asked).toEqual([]);
  expect(written).toEqual({});
});

test('a failover account is known when it is already in providers.json, or when a --<role> flag declares it', async () => {
  const held = { providers: { claude: { harness: 'claude' }, 'claude-work': { harness: 'claude', configDir: '/w' }, codex: { harness: 'codex' } } };
  const { deps, written } = fakeDeps({ exists: (path) => path.endsWith('providers.json'), readConfig: asFiles(held) });
  const out = join(dir, 'held-failover.json');
  await runInit({ repo: ['A/b'], yes: true, out, authorFailover: ['claude-work'] }, quietUi().ui, deps, join(dir, 'held-home'));
  expect(JSON.parse(written[out]!).failover.roles.author).toEqual([{ provider: 'claude-work' }]);

  const declared = fakeDeps();
  const outDeclared = join(dir, 'declared-failover.json');
  await runInit({ repo: ['A/b'], yes: true, out: outDeclared, author: 'claude:sonnet', reviewer: 'codex:m', reviewerFailover: ['claude:opus'] }, quietUi().ui, declared.deps);
  expect(JSON.parse(declared.written[outDeclared]!).failover.roles.reviewer).toEqual([{ provider: 'claude', model: 'opus' }]);
});

test('failover flags write their steps to failover.roles.<role>, in the order given, and the role is not asked its failover', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'steps.json');
  await runInit({ repo: ['A/b'], out, authorFailover: ['codex:gpt-x', 'claude:llama3:8b'], leadReviewer: 'codex:gpt-test', leadReviewerFailover: ['claude'] }, ui, deps);
  const failover = JSON.parse(written[out]!).failover;
  expect(failover.roles.author).toEqual([{ provider: 'codex', model: 'gpt-x' }, { provider: 'claude', model: 'llama3:8b' }]);
  expect(failover.roles.leadReviewer).toEqual([{ provider: 'claude' }]); // no model: the account's, then the harness's
  expect(failover.roles.reviewer).toBeUndefined();
  expect(asked.filter((question) => /failover/i.test(question))).toEqual(['Turn failover on for the reviewer? When it runs out of credits it moves to the steps you list, each an account and a model.']);
});

test('under --yes the flagged steps are written and nothing about failover is asked', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'yes-steps.json');
  await runInit({ repo: ['A/b'], yes: true, out, reviewerFailover: ['claude:opus'] }, ui, deps);
  expect(JSON.parse(written[out]!).failover.roles).toEqual({ reviewer: [{ provider: 'claude', model: 'opus' }] });
  expect(asked.some((question) => /failover/i.test(question))).toBe(false);
  expect(providersWritten(written)).toEqual({ claude: { harness: 'claude' }, codex: { harness: 'codex' } });
});

test('a step that is the role\'s own account and model is refused, whether the role came from a flag or from a question', async () => {
  await expect(runInit({ repo: ['A/b'], yes: true, out: join(dir, 'own1.json'), author: 'claude:sonnet', authorFailover: ['claude:sonnet'] }, quietUi().ui, fakeDeps().deps)).rejects.toThrow(`--author-failover "claude:sonnet": that is the author's own account and model`);
  // not flagged: the author starts on claude sonnet by itself
  const { deps, written } = fakeDeps();
  await expect(runInit({ repo: ['A/b'], yes: true, out: join(dir, 'own2.json'), authorFailover: ['claude:sonnet'] }, quietUi().ui, deps)).rejects.toThrow(`--author-failover "claude:sonnet": that is the author's own account and model`);
  expect(written).toEqual({});
  // no model is never the role's own
  await runInit({ repo: ['A/b'], yes: true, out: join(dir, 'own3.json'), authorFailover: ['claude'] }, quietUi().ui, deps);
  expect(JSON.parse(written[join(dir, 'own3.json')]!).failover.roles.author).toEqual([{ provider: 'claude' }]);
});

test('failover flags replace the failover the file has, without asking to keep it', async () => {
  const withFailover = {
    repos: [{ name: 'X/y' }],
    profiles: { 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' }, gh: { kind: 'gh' } },
    orchestratorProfile: 'tassadar-agent',
    providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } },
    agents: { author: { profile: 'tassadar-agent', provider: 'claude', model: 'opus' }, reviewer: { profile: 'gh', provider: 'codex', model: 'gpt-test' } },
    failover: { triggers: ['usage_limit'], roles: { author: [{ provider: 'codex', model: 'old' }] } },
  };
  const folder = join(dir, 'edit-home');
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(withFailover) });
  const { ui, asked } = quietUi();
  await runInit({ authorFailover: ['codex:new'] }, ui, deps, folder);
  expect(JSON.parse(written[join(folder, 'engine.json')]!).failover).toEqual({ triggers: ['usage_limit'], roles: { author: [{ provider: 'codex', model: 'new' }] } });
  expect(asked.some((question) => question.startsWith('Keep the failover you have?') && question.includes('author'))).toBe(false);
});

test('--orchestrator-profile answers the orchestrator question and is the profile written', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'orchestrator.json');
  await runInit({ repo: ['A/b'], out, orchestratorProfile: 'gh' }, ui, deps);
  expect(asked.some((question) => question.startsWith('GitHub profile for the orchestrator'))).toBe(false);
  expect(JSON.parse(written[out]!).orchestratorProfile).toBe('gh');
});
