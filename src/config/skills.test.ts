import { describe, expect, test } from 'vitest';
import { defaultSkills, resolveReviewSkills, resolveSkills, savedSkills, solveSkills } from './skills.ts';

const own = (name: string) => ({ name, named: true });

describe('resolveSkills', () => {
  test('with nothing named it is Solve\'s defaults, none of them named', () => {
    expect(resolveSkills(solveSkills)).toEqual(defaultSkills);
  });

  test('the global wins over Solve\'s defaults and counts as named only when it differs', () => {
    expect(resolveSkills({ ship: 'my-ship', review: { review: 'code-review', publish: null }, fix: 'code-resolve' })).toEqual({
      ship: own('my-ship'),
      review: { review: { name: 'code-review', named: false }, publish: null },
      fix: { name: 'code-resolve', named: false },
    });
  });

  test('the repo wins over the global, the role over the repo, and a repo\'s role over the global role', () => {
    const global = { ship: 'g-ship', review: { review: 'g-review', publish: 'g-publish' }, fix: 'g-fix' };
    const repo = { ship: 'r-ship', fix: 'r-fix', review: { review: 'r-review' } };
    expect(resolveSkills(global, repo)).toEqual({ ship: own('r-ship'), review: { review: own('r-review'), publish: own('g-publish') }, fix: own('r-fix') });
    expect(resolveSkills(global, repo, { ship: 'a-ship' }, { review: { review: 'v-review' } })).toMatchObject({ ship: own('a-ship'), fix: own('r-fix'), review: { review: own('v-review') } });
    expect(resolveSkills(global, repo, { ship: 'a-ship' }, undefined, { ship: 'ra-ship' })).toMatchObject({ ship: own('ra-ship') });
  });

  test('review merges one level in: a level naming review keeps the publish below it, and null at a level is a value', () => {
    const global = { ship: 'ship', review: { review: 'g-review', publish: 'g-publish' }, fix: 'fix' };
    expect(resolveSkills(global, { review: { publish: null } }).review).toEqual({ review: own('g-review'), publish: null });
    expect(resolveSkills(global, { review: { publish: null } }, undefined, { review: { publish: 'x' } }).review.publish).toEqual(own('x'));
  });

  test('a skill named at a level counts as named even when it is Solve\'s own name', () => {
    expect(resolveSkills(solveSkills, { ship: 'ship' }).ship).toEqual(own('ship'));
  });
});

describe('resolveReviewSkills', () => {
  const global = { ...solveSkills, review: { review: 'g-review', publish: 'g-publish' } };
  const none = { ...solveSkills };

  test('the lead with nothing named is Solve\'s review skills, none of them named', () => {
    expect(resolveReviewSkills('lead', none, undefined)).toEqual(defaultSkills.review);
    expect(resolveReviewSkills('review', none, undefined)).toEqual(defaultSkills.review);
  });

  test('the lead takes its own, then the repo\'s skills.lead, then the global skills.lead', () => {
    const globalLead = { ...global, lead: { review: 'gl-review', publish: 'gl-publish' } };
    const repo = { lead: { review: 'rl-review' }, review: { review: 'r-review' } };
    expect(resolveReviewSkills('lead', globalLead, repo, { review: 'own-review' })).toEqual({ review: own('own-review'), publish: own('gl-publish') });
    expect(resolveReviewSkills('lead', globalLead, repo)).toEqual({ review: own('rl-review'), publish: own('gl-publish') });
    expect(resolveReviewSkills('lead', globalLead, undefined)).toEqual({ review: own('gl-review'), publish: own('gl-publish') });
    // a stronger level among the lead's own wins, and null is a value
    expect(resolveReviewSkills('lead', globalLead, repo, { publish: 'weak' }, { publish: null }).publish).toBeNull();
  });

  test('what no level names for the lead comes from the repo\'s skills.review, then the global, then Solve\'s, and a skills.review the person named is named', () => {
    expect(resolveReviewSkills('lead', global, { review: { review: 'r-review' } })).toEqual({ review: own('r-review'), publish: own('g-publish') });
    expect(resolveReviewSkills('lead', global, undefined)).toEqual({ review: own('g-review'), publish: own('g-publish') });
    expect(resolveReviewSkills('lead', { ...none, review: { review: 'code-review', publish: null } }, undefined)).toEqual({ review: { name: 'code-review', named: false }, publish: null });
    expect(resolveReviewSkills('lead', none, { review: { publish: null } }, { review: 'x' })).toEqual({ review: own('x'), publish: null });
  });

  test('an extra reviewer takes its own entry, the repo\'s skills.review, the global and Solve\'s, and ignores skills.lead', () => {
    const withLead = { ...global, lead: { review: 'gl-review' } };
    const repo = { lead: { review: 'rl-review' }, review: { review: 'r-review' } };
    expect(resolveReviewSkills('review', withLead, repo, { publish: null })).toEqual({ review: own('r-review'), publish: null });
    expect(resolveReviewSkills('review', withLead, undefined, { review: 'mine' })).toEqual({ review: own('mine'), publish: own('g-publish') });
    expect(resolveReviewSkills('review', none, undefined)).toEqual(defaultSkills.review);
  });
});

test('an epic saved without skills reads Solve\'s defaults, none named', () => {
  expect(savedSkills(null)).toEqual(defaultSkills);
  expect(savedSkills({})).toEqual(defaultSkills);
  expect(savedSkills({ skills: resolveSkills(solveSkills, { fix: 'x' }) }).fix).toEqual(own('x'));
});
