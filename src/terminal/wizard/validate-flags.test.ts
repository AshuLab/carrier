import { expect, test } from 'vitest';
import type { InitFlags } from './flags.ts';
import { failoverProblem, failoverSteps, flagProblem } from './validate-flags.ts';

const ok: InitFlags = { repo: ['A/b'], yes: true };

test('flags with nothing wrong, or none, have no problem', () => {
  expect(flagProblem({})).toBeUndefined();
  expect(flagProblem(ok)).toBeUndefined();
  expect(flagProblem({ ...ok, author: 'claude:sonnet', authorProfile: 'forge:artanis-agent', orchestratorProfile: 'forge:artanis-agent', authorProvider: 'ollama', authorEffort: 'max', authorPersonaName: 'Ada', authorPersonaPrompt: 'Terse.', reviewerProfile: 'gh', leadReviewerEffort: 'low' })).toBeUndefined();
});

test.each([
  ['an effort outside the five levels', { authorEffort: 'turbo' }, '--author-effort "turbo": expected low, medium, high, xhigh, max'],
  ['an empty effort', { reviewerEffort: '' }, '--reviewer-effort ""'],
  ['the lead reviewer\'s effort', { leadReviewerEffort: 'Max' }, '--lead-reviewer-effort "Max"'],
  ['an agent that is not <harness>:<model>', { reviewer: 'codex' }, '--reviewer: '],
  ['an unknown harness', { author: 'gemini:x' }, '--author: '],
  ['a profile that is neither forge:<agent> nor gh', { leadReviewerProfile: 'me' }, '--lead-reviewer-profile: '],
  ['a provider that is not a local server', { authorProvider: 'cloud' }, '--author-provider: '],
  ['a persona name with a line break', { authorPersonaName: 'a\nb' }, '--author-persona-name: '],
  ['a persona prompt that is blank', { reviewerPersonaPrompt: '  ' }, '--reviewer-persona-prompt: '],
  ['an orchestrator profile that is neither forge:<agent> nor gh', { orchestratorProfile: 'me' }, '--orchestrator-profile: '],
  ['a repo that is not owner/name', { repo: ['A/b', 'ab'] }, '--repo "ab": must be owner/name'],
  ['--yes with no repo', { yes: true }, '--repo'],
  ['--yes with an empty repo list', { yes: true, repo: [] }, '--repo'],
] as [string, InitFlags, string][])('%s is refused naming its flag', (_name, flags, expected) => {
  expect(flagProblem(flags)).toContain(expected);
});

test('the first problem found is the one reported', () => {
  expect(flagProblem({ authorEffort: 'turbo', reviewerEffort: 'nope', repo: ['x'], yes: true })).toContain('--author-effort');
  expect(flagProblem({ repo: ['x'], yes: true })).toContain('--repo "x"');
});

test('no --repo is fine when nothing says --yes: the wizard asks for them', () => {
  expect(flagProblem({ author: 'claude:sonnet' })).toBeUndefined();
});

test.each([
  ['an empty step', '', '--author-failover ""'],
  ['a step with no account', ':m', '--author-failover ":m"'],
  ['a colon with an empty model', 'a:', '--author-failover "a:"'],
  ['a colon with a blank model', 'a: ', '--author-failover "a: "'],
  ['an account in capitals', 'Claude:opus', '--author-failover "Claude:opus"'],
  ['an account that starts with a digit', '1a', '--author-failover "1a"'],
  ['an account over 40 characters', `a${'b'.repeat(40)}`, '--author-failover'],
])('failover: %s is refused, naming the flag', (_name, step, expected) => {
  expect(flagProblem({ ...ok, authorFailover: [step] })).toContain(expected);
  expect(flagProblem({ ...ok, reviewerFailover: ['codex', step] })).toContain('--reviewer-failover');
});

test('failover: a model may hold colons, so claude:llama3:8b is account claude with model llama3:8b', () => {
  const flags: InitFlags = { ...ok, authorFailover: ['claude:llama3:8b', 'codex'] };
  expect(flagProblem(flags)).toBeUndefined();
  expect(failoverSteps(flags, 'author')).toEqual([{ provider: 'claude', model: 'llama3:8b' }, { provider: 'codex' }]);
  expect(failoverSteps(flags, 'reviewer')).toBeUndefined();
});

test('failover: at most two steps and no step twice', () => {
  expect(flagProblem({ ...ok, leadReviewerFailover: ['a', 'b', 'c'] })).toContain('--lead-reviewer-failover: at most 2 steps');
  expect(flagProblem({ ...ok, authorFailover: ['codex:m', 'codex:m'] })).toContain('--author-failover "codex:m": it repeats an earlier step');
  expect(flagProblem({ ...ok, authorFailover: ['codex', 'codex:m'] })).toBeUndefined();
});

test('failover: an account that is not among the known ones is refused naming the flag and the accounts there are', () => {
  const flags: InitFlags = { ...ok, reviewerFailover: ['codex', 'ghost:m'] };
  expect(flagProblem(flags)).toBeUndefined(); // it parses; whether the account exists needs the accounts
  expect(failoverProblem(flags, ['claude', 'codex'], {})).toBe('--reviewer-failover "ghost:m": there is no account named "ghost" (accounts: claude, codex)');
  expect(failoverProblem(flags, ['claude', 'codex', 'ghost'], {})).toBeUndefined();
  expect(failoverProblem({}, [], {})).toBeUndefined();
});

test('failover: a step with the role\'s own account and model is refused, and a step with no model never is', () => {
  const own = { author: { provider: 'claude', model: 'sonnet' } };
  expect(failoverProblem({ authorFailover: ['claude:sonnet'] }, ['claude'], own)).toBe('--author-failover "claude:sonnet": that is the author\'s own account and model, so it would move nowhere');
  expect(failoverProblem({ authorFailover: ['codex', 'claude:sonnet'] }, ['claude', 'codex'], own)).toContain('--author-failover');
  expect(failoverProblem({ authorFailover: ['claude'] }, ['claude'], own)).toBeUndefined();
  expect(failoverProblem({ authorFailover: ['claude:opus'] }, ['claude'], own)).toBeUndefined();
  expect(failoverProblem({ leadReviewerFailover: ['claude:sonnet'] }, ['claude'], { 'lead-reviewer': { provider: 'claude', model: 'sonnet' } })).toContain('the lead reviewer\'s own account');
  expect(failoverProblem({ reviewerFailover: ['claude:sonnet'] }, ['claude'], own)).toBeUndefined(); // the author's pair is not the reviewer's
});
