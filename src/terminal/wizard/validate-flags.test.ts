import { expect, test } from 'vitest';
import type { InitFlags } from './flags.ts';
import { extraFailoverProblem, failoverProblem, failoverSteps, flagProblem, parseExtras } from './validate-flags.ts';

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

// The flags that name an extra reviewer.

test('--extra-reviewer creates the reviewers in the order given, and each field flag sets that field of the reviewer it names and no other', () => {
  const flags: InitFlags = {
    ...ok,
    extraReviewer: ['Seguridad API=claude:sonnet', 'Usabilidad=codex:gpt-5'],
    extraReviewerType: ['usabilidad=ux'], // a name is compared without regard to case
    extraReviewerProfile: ['Seguridad API=forge:sentinel'],
    extraReviewerEffort: ['Usabilidad=high'],
    extraReviewerProvider: ['Seguridad API=ollama'],
    extraReviewerPersonaName: ['Usabilidad=Ada'],
    extraReviewerPersonaPrompt: ['Usabilidad=Be terse. a=b'],
    extraReviewerFailover: ['Seguridad API=codex:gpt-5', 'Usabilidad=claude', 'Seguridad API=claude'],
  };
  expect(flagProblem(flags)).toBeUndefined();
  expect(parseExtras(flags).reviewers).toEqual([
    { name: 'Seguridad API', agent: 'claude:sonnet', profile: 'forge:sentinel', provider: 'ollama', failover: ['codex:gpt-5', 'claude'] },
    { name: 'Usabilidad', agent: 'codex:gpt-5', type: 'ux', effort: 'high', personaName: 'Ada', personaPrompt: 'Be terse. a=b', failover: ['claude'] },
  ]);
});

test('the name is everything before the first =, and what follows may hold more', () => {
  expect(parseExtras({ extraReviewer: ['a=claude:m=1'] }).reviewers).toEqual([{ name: 'a', agent: 'claude:m=1', failover: [] }]);
});

test.each([
  ['a field flag that names no reviewer', { extraReviewer: ['A=claude:m'], extraReviewerType: ['B=ux'] }, '--extra-reviewer-type "B=ux": no --extra-reviewer is named "B"'],
  ['a field flag with no --extra-reviewer', { extraReviewerEffort: ['A=high'] }, '--extra-reviewer-effort "A=high": no --extra-reviewer'],
  ['a fourth --extra-reviewer', { extraReviewer: ['a=claude:m', 'b=claude:m', 'c=claude:m', 'd=claude:m'] }, '--extra-reviewer: at most 3 extra reviewers, 4 were given'],
  ['a name given twice without regard to case', { extraReviewer: ['Seg=claude:m', 'SEG=codex:m'] }, '--extra-reviewer "SEG=codex:m": another extra reviewer already has that name'],
  ['a blank name', { extraReviewer: ['  =claude:m'] }, '--extra-reviewer "  =claude:m": a name is required'],
  ['a name over 40 characters', { extraReviewer: [`${'a'.repeat(41)}=claude:m`] }, '--extra-reviewer'],
  ['a name with a line break', { extraReviewer: ['a\nb=claude:m'] }, 'must be one line'],
  ['a value with no =', { extraReviewer: ['claude:m'] }, '--extra-reviewer "claude:m": expected "<name>=<value>"'],
  ['a field value with no =', { extraReviewer: ['A=claude:m'], extraReviewerType: ['ux'] }, '--extra-reviewer-type "ux": expected "<name>=<value>"'],
  ['an agent that is not <harness>:<model>', { extraReviewer: ['A=claude'] }, '--extra-reviewer: '],
  ['a type that is not a slug', { extraReviewer: ['A=claude:m'], extraReviewerType: ['A=Not A Slug'] }, '--extra-reviewer-type "Not A Slug"'],
  ['a type given twice for one reviewer', { extraReviewer: ['A=claude:m'], extraReviewerType: ['A=ux', 'a=ui'] }, '--extra-reviewer-type "a=ui": "A" already has one'],
  ['an effort that is not a level', { extraReviewer: ['A=claude:m'], extraReviewerEffort: ['A=turbo'] }, '--extra-reviewer-effort "turbo"'],
  ['a profile that is neither forge:<agent> nor gh', { extraReviewer: ['A=claude:m'], extraReviewerProfile: ['A=me'] }, '--extra-reviewer-profile: '],
  ['a provider that is not a local server', { extraReviewer: ['A=claude:m'], extraReviewerProvider: ['A=cloud'] }, '--extra-reviewer-provider: '],
  ['a persona that is empty', { extraReviewer: ['A=claude:m'], extraReviewerPersonaName: ['A='] }, '--extra-reviewer-persona-name: '],
  ['a malformed failover step', { extraReviewer: ['A=claude:m'], extraReviewerFailover: ['A=codex:'] }, '--extra-reviewer-failover "codex:"'],
  ['a third failover step', { extraReviewer: ['A=claude:m'], extraReviewerFailover: ['A=a', 'A=b', 'A=c'] }, '--extra-reviewer-failover: at most 2 steps'],
] as [string, InitFlags, string][])('extra reviewer flags: %s is refused, naming its flag', (_name, flags, expected) => {
  expect(flagProblem({ ...ok, ...flags })).toContain(expected);
  expect(parseExtras(flags).reviewers).toEqual([]);
});

test('extra reviewer failover: an account that is not known is refused naming the flag, and a step that is the reviewer\'s own account and model', () => {
  const { reviewers } = parseExtras({ extraReviewer: ['A=claude:m', 'B=codex:n'], extraReviewerFailover: ['B=ghost:m'] });
  expect(extraFailoverProblem(reviewers, ['claude', 'codex'], [{ provider: 'claude', model: 'm' }, { provider: 'codex', model: 'n' }])).toBe('--extra-reviewer-failover "ghost:m": there is no account named "ghost" (accounts: claude, codex)');
  expect(extraFailoverProblem(reviewers, ['claude', 'codex', 'ghost'], [{ provider: 'claude', model: 'm' }, { provider: 'codex', model: 'n' }])).toBeUndefined();
  const own = parseExtras({ extraReviewer: ['A=claude:m'], extraReviewerFailover: ['A=claude:m'] }).reviewers;
  expect(extraFailoverProblem(own, ['claude'], [{ provider: 'claude', model: 'm' }])).toContain("that is the extra reviewer A's own account and model");
});
