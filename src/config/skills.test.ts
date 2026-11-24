import { describe, expect, test } from 'vitest';
import { defaultSkills, resolveSkills, savedSkills, solveSkills } from './skills.ts';

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

test('an epic saved without skills reads Solve\'s defaults, none named', () => {
  expect(savedSkills(null)).toEqual(defaultSkills);
  expect(savedSkills({})).toEqual(defaultSkills);
  expect(savedSkills({ skills: resolveSkills(solveSkills, { fix: 'x' }) }).fix).toEqual(own('x'));
});
