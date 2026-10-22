import { expect, test } from 'vitest';
import { parseCallerResult, type Expected } from './caller-result.ts';

const expected: Expected = { executionId: 'e1', repo: 'AshuLab/carrier', epic: 3, stage: 'review' };
const sha = 'a'.repeat(40);
const completed = {
  ...expected,
  outcome: 'completed',
  summary: 'done',
  pr: { number: 7, headSha: sha },
  verification: { ci: 'passed', evidence: 'pnpm test green' },
};
const changes = { ...expected, outcome: 'changes_requested', summary: 's', pr: completed.pr, blockers: [{ title: 'bug' }] };
const human = { ...expected, outcome: 'needs_human', summary: 's', reason: 'stuck' };
const parse = (value: unknown, exp = expected) => parseCallerResult(JSON.stringify(value), exp);

test.each([completed, changes, human, { ...completed, verification: { ci: 'absent', evidence: 'no CI' } }])(
  'accepts a valid result',
  (value) => {
    expect(parse(value)).toEqual({ ok: true, result: value });
  },
);

test('missing file, empty, truncated and non-JSON are invalid', () => {
  for (const raw of [null, '', '   ', '{"outcome":"compl', 'not json']) {
    expect(parseCallerResult(raw, expected)).toMatchObject({ ok: false, kind: 'invalid' });
  }
});

test.each([
  ['array', []],
  ['string', 'x'],
  ['null', null],
  ['number', 3],
  ['empty object', {}],
  ['unknown outcome', { ...human, outcome: 'done' }],
  ['wrong type', { ...completed, epic: '3' }],
  ['short sha', { ...completed, pr: { number: 7, headSha: 'abc123' } }],
  ['uppercase sha', { ...completed, pr: { number: 7, headSha: 'A'.repeat(40) } }],
  ['epic 0', { ...completed, epic: 0 }],
  ['epic not an integer', { ...completed, epic: 3.5 }],
  ['repo with extra slash', { ...completed, repo: 'AshuLab/carrier/x' }],
  ['repo with newline', { ...completed, repo: 'AshuLab/carrier\n' }],
  ['repo with newline inside', { ...completed, repo: 'AshuLab\n/carrier' }],
  ['empty blockers', { ...changes, blockers: [] }],
  ['changes_requested outside review', { ...changes, stage: 'fix' }],
  ['failed CI', { ...completed, verification: { ci: 'failed', evidence: 'red' } }],
  ['completed without verification', { ...completed, verification: undefined }],
])('rejects %s', (_name, value) => {
  expect(parse(value, { ...expected, stage: 'fix' })).toMatchObject({ ok: false, kind: expect.stringMatching(/invalid|mismatch/) });
  expect(parse(value)).toMatchObject({ ok: false, kind: 'invalid' });
});

test.each([
  ['executionId', { ...completed, executionId: 'other' }],
  ['repo', { ...completed, repo: 'AshuLab/other' }],
  ['epic', { ...completed, epic: 4 }],
  ['stage', { ...completed, stage: 'ship' }],
])('a well-formed result with another %s is a mismatch, not invalid', (_name, value) => {
  expect(parse(value)).toMatchObject({ ok: false, kind: 'mismatch' });
});

// --- stable blocker ids and `resolved` (both optional) ---
const withIds = { ...changes, blockers: [{ id: 'token-expiry', title: 'Token expiry' }, { title: 'No id here' }], resolved: ['old-one'] };

test.each([withIds, { ...changes, resolved: [] }, { ...completed, resolved: ['old-one'] }])('accepts ids and resolved, and keeps them', (value) => {
  expect(parse(value)).toEqual({ ok: true, result: value });
});

test('a result without ids or resolved still validates (old results)', () => {
  expect(parse(changes)).toMatchObject({ ok: true });
  expect(parse(completed)).toMatchObject({ ok: true });
});

test.each([
  ['a numeric blocker id', { ...changes, blockers: [{ id: 7, title: 'x' }] }],
  ['an empty blocker id', { ...changes, blockers: [{ id: '', title: 'x' }] }],
  ['a very long id', { ...changes, blockers: [{ id: 'a'.repeat(65), title: 'x' }] }],
  ['resolved that is not a list', { ...changes, resolved: 'a' }],
  ['resolved with a number', { ...changes, resolved: [1] }],
  ['duplicate blocker ids in a round', { ...changes, blockers: [{ id: 'a', title: 'x' }, { id: 'a', title: 'y' }] }],
  ['duplicate resolved ids', { ...changes, resolved: ['a', 'a'] }],
  ['a resolved id that is still a blocker', { ...changes, blockers: [{ id: 'a', title: 'x' }], resolved: ['a'] }],
  ['an oversize blocker list', { ...changes, blockers: Array.from({ length: 51 }, (_, i) => ({ id: `b${i}`, title: 'x' })) }],
  ['an oversize resolved list', { ...completed, resolved: Array.from({ length: 51 }, (_, i) => `r${i}`) }],
])('rejects %s', (_name, value) => {
  expect(parse(value)).toMatchObject({ ok: false, kind: 'invalid' });
});

// --- observations (completed only, optional) ---
const obs = { ...completed, observations: [{ id: 'naming', title: 'Rename x', url: 'https://github.com/AshuLab/carrier/pull/7#discussion_r1' }, { title: 'No id, no url' }] };

test.each([obs, { ...completed, observations: [] }])('accepts a completed result with observations, or an empty list, and keeps them', (value) => {
  expect(parse(value)).toEqual({ ok: true, result: value });
});

test.each([
  ['a duplicate observation id', { ...completed, observations: [{ id: 'a', title: 'x' }, { id: 'a', title: 'y' }] }],
  ['an oversize observation list', { ...completed, observations: Array.from({ length: 51 }, (_, i) => ({ id: `o${i}`, title: 'x' })) }],
  ['an empty observation title', { ...completed, observations: [{ title: '' }] }],
  ['an observation without a title', { ...completed, observations: [{ id: 'a' }] }],
  ['a bad observation url', { ...completed, observations: [{ title: 'x', url: 'not a url' }] }],
  ['a numeric observation id', { ...completed, observations: [{ id: 7, title: 'x' }] }],
  ['observations that is not a list', { ...completed, observations: 'x' }],
])('rejects %s', (_name, value) => {
  expect(parse(value)).toMatchObject({ ok: false, kind: 'invalid' });
});
