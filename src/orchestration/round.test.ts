import { expect, test } from 'vitest';
import { decideRound, type NoVerdict, type Verdict } from './round.ts';

const base = { executionId: 'e', repo: 'AshuLab/a', epic: 1 };
const pr = { number: 50, headSha: 'a'.repeat(40) };
const done = (slot: Verdict['slot'], observations: { title: string }[] = [], evidence: string = slot): Verdict => ({ slot, result: { ...base, stage: 'review', outcome: 'completed', summary: 's', pr, verification: { ci: 'passed', evidence }, observations } });
const asks = (slot: Verdict['slot']): Verdict => ({ slot, result: { ...base, stage: 'review', outcome: 'changes_requested', summary: 's', pr, blockers: [{ title: 'fix it' }] } });

test('a round waits while a slot has no verdict', () => {
  expect(decideRound(['reviewer', 'reviewer-2'], [done('reviewer')])).toEqual({ kind: 'waiting' });
  expect(decideRound(['reviewer', 'reviewer-2'], [])).toEqual({ kind: 'waiting' });
});

test('any verdict that asks for changes decides the round for changes, once every slot has one', () => {
  expect(decideRound(['reviewer', 'reviewer-2'], [done('reviewer'), asks('reviewer-2')])).toEqual({ kind: 'changes_requested' });
  expect(decideRound(['reviewer', 'reviewer-2'], [asks('reviewer-2'), asks('reviewer')])).toEqual({ kind: 'changes_requested' });
});

test('when every verdict completed the round is agreed: observations of all with their slot, and the first slot\'s verification', () => {
  const decision = decideRound(['reviewer', 'reviewer-2'], [done('reviewer-2', [{ title: 'b' }]), done('reviewer', [{ title: 'a' }])]);
  expect(decision).toEqual({ kind: 'completed', observations: [{ title: 'a', slot: 'reviewer' }, { title: 'b', slot: 'reviewer-2' }], verification: { ci: 'passed', evidence: 'reviewer' } });
});

test('a slot\'s newest verdict stands over its older one on the same head', () => {
  expect(decideRound(['reviewer'], [asks('reviewer'), done('reviewer')]).kind).toBe('completed');
});

const none = (slot: Verdict['slot'], kind: NoVerdict['kind'] = 'agent_needs_human'): NoVerdict => ({ slot, kind, why: `${slot} gave none` });

test('a slot with no verdict is absent: one verdict out of two decides the round', () => {
  expect(decideRound(['reviewer', 'reviewer-2'], [done('reviewer', [{ title: 'a' }])], [none('reviewer-2')])).toEqual({ kind: 'completed', observations: [{ title: 'a', slot: 'reviewer' }], verification: { ci: 'passed', evidence: 'reviewer' } });
  expect(decideRound(['reviewer', 'reviewer-2'], [asks('reviewer-2')], [none('reviewer')])).toEqual({ kind: 'changes_requested' });
});

test('the verification of a round is the first slot with a verdict\'s when the mandatory reviewer gave none', () => {
  expect(decideRound(['reviewer', 'reviewer-2', 'reviewer-3'], [done('reviewer-3', [], 'third')], [none('reviewer'), none('reviewer-2')])).toMatchObject({ kind: 'completed', verification: { evidence: 'third' } });
});

test('a round waits while a slot has neither a verdict nor a reason for none', () => {
  expect(decideRound(['reviewer', 'reviewer-2', 'reviewer-3'], [done('reviewer')], [none('reviewer-2')])).toEqual({ kind: 'waiting' });
});

test('with no verdict at all the round failed, each slot with its reason', () => {
  const decision = decideRound(['reviewer', 'reviewer-2'], [], [none('reviewer-2', 'skill_missing'), none('reviewer')]);
  expect(decision).toEqual({ kind: 'failed', none: [none('reviewer'), none('reviewer-2', 'skill_missing')] });
});

test('a reason that came later for a slot stands over the older one', () => {
  expect(decideRound(['reviewer'], [], [none('reviewer'), { ...none('reviewer', 'usage_limit'), why: 'later' }])).toMatchObject({ kind: 'failed', none: [{ why: 'later' }] });
});
