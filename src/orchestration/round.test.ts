import { expect, test } from 'vitest';
import { decideRound, type NoVerdict, type Verdict } from './round.ts';

const base = { executionId: 'e', repo: 'AshuLab/a', epic: 1 };
const pr = { number: 50, headSha: 'a'.repeat(40) };
const done = (slot: Verdict['slot'], observations: { title: string }[] = [], evidence: string = slot): Verdict => ({ slot, result: { ...base, stage: 'review', outcome: 'completed', summary: 's', pr, verification: { ci: 'passed', evidence }, observations } });
const asks = (slot: Verdict['slot']): Verdict => ({ slot, result: { ...base, stage: 'review', outcome: 'changes_requested', summary: 's', pr, blockers: [{ title: 'fix it' }] } });

test('a round waits while a slot has no verdict', () => {
  expect(decideRound(['reviewer', 'seguridad-api'], [done('reviewer')])).toEqual({ kind: 'waiting' });
  expect(decideRound(['reviewer', 'seguridad-api'], [])).toEqual({ kind: 'waiting' });
});

test('any verdict that asks for changes decides the round for changes, once every slot has one', () => {
  expect(decideRound(['reviewer', 'seguridad-api'], [done('reviewer'), asks('seguridad-api')])).toEqual({ kind: 'changes_requested' });
  expect(decideRound(['reviewer', 'seguridad-api'], [asks('seguridad-api'), asks('reviewer')])).toEqual({ kind: 'changes_requested' });
});

test('when every verdict completed the round is agreed: observations of all with their slot, and the first slot\'s verification', () => {
  const decision = decideRound(['reviewer', 'seguridad-api'], [done('seguridad-api', [{ title: 'b' }]), done('reviewer', [{ title: 'a' }])]);
  expect(decision).toEqual({ kind: 'completed', observations: [{ title: 'a', slot: 'reviewer' }, { title: 'b', slot: 'seguridad-api' }], verification: { ci: 'passed', evidence: 'reviewer' } });
});

test('a slot\'s newest verdict stands over its older one on the same head', () => {
  expect(decideRound(['reviewer'], [asks('reviewer'), done('reviewer')]).kind).toBe('completed');
});

const none = (slot: Verdict['slot'], kind: NoVerdict['kind'] = 'agent_needs_human'): NoVerdict => ({ slot, kind, why: `${slot} gave none` });

test('a slot with no verdict is absent: one verdict out of two decides the round', () => {
  expect(decideRound(['reviewer', 'seguridad-api'], [done('reviewer', [{ title: 'a' }])], [none('seguridad-api')])).toEqual({ kind: 'completed', observations: [{ title: 'a', slot: 'reviewer' }], verification: { ci: 'passed', evidence: 'reviewer' } });
  expect(decideRound(['reviewer', 'seguridad-api'], [asks('seguridad-api')], [none('reviewer')])).toEqual({ kind: 'changes_requested' });
});

test('the verification of a round is the first slot with a verdict\'s when the mandatory reviewer gave none', () => {
  expect(decideRound(['reviewer', 'seguridad-api', 'usabilidad'], [done('usabilidad', [], 'third')], [none('reviewer'), none('seguridad-api')])).toMatchObject({ kind: 'completed', verification: { evidence: 'third' } });
});

test('a round waits while a slot has neither a verdict nor a reason for none', () => {
  expect(decideRound(['reviewer', 'seguridad-api', 'usabilidad'], [done('reviewer')], [none('seguridad-api')])).toEqual({ kind: 'waiting' });
});

test('with no verdict at all the round failed, each slot with its reason', () => {
  const decision = decideRound(['reviewer', 'seguridad-api'], [], [none('seguridad-api', 'skill_missing'), none('reviewer')]);
  expect(decision).toEqual({ kind: 'failed', none: [none('reviewer'), none('seguridad-api', 'skill_missing')] });
});

test('a reason that came later for a slot stands over the older one', () => {
  expect(decideRound(['reviewer'], [], [none('reviewer'), { ...none('reviewer', 'usage_limit'), why: 'later' }])).toMatchObject({ kind: 'failed', none: [{ why: 'later' }] });
});

test('a slot with blockers still open that gave no verdict does not let completed verdicts close the round: it fails naming that slot', () => {
  const decision = decideRound(['reviewer', 'seguridad-api'], [done('reviewer')], [none('seguridad-api')], ['seguridad-api']);
  expect(decision).toEqual({ kind: 'open_blockers', none: [none('seguridad-api')] });
});

test('every slot with open blockers and no verdict is named, and one with none open is left out', () => {
  const decision = decideRound(['reviewer', 'seguridad-api', 'usabilidad'], [done('reviewer')], [none('seguridad-api'), none('usabilidad')], ['usabilidad', 'seguridad-api']);
  expect(decision).toEqual({ kind: 'open_blockers', none: [none('seguridad-api'), none('usabilidad')] });
  expect(decideRound(['reviewer', 'seguridad-api', 'usabilidad'], [done('reviewer')], [none('seguridad-api'), none('usabilidad')], ['usabilidad'])).toEqual({ kind: 'open_blockers', none: [none('usabilidad')] });
});

test('another slot that asks for changes lets the round go on to the fix, which answers the open blockers too', () => {
  expect(decideRound(['reviewer', 'seguridad-api'], [asks('reviewer')], [none('seguridad-api')], ['seguridad-api'])).toEqual({ kind: 'changes_requested' });
});

test('open blockers of a slot that gave a verdict in the round are its own verdict to stand, not a silence', () => {
  expect(decideRound(['reviewer', 'seguridad-api'], [done('reviewer'), done('seguridad-api')], [], ['seguridad-api']).kind).toBe('completed');
});
