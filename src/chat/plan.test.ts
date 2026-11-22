import { expect, test } from 'vitest';
import { plan } from './plan.ts';

test('a plan for a new project still parses with the kind an older app sends', () => {
  const sent = { workspace: { kind: 'project', name: 'my-app' }, agent: 'claude', text: 'hi' };
  expect(plan.parse(sent).workspace).toEqual({ kind: 'project', name: 'my-app' });
  expect(plan.safeParse({ ...sent, branch: 'main' }).success).toBe(false); // a new project has no commits
});
