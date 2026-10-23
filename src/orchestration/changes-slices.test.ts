import { expect, test } from 'vitest';
import { changesSlices } from './changes-slices.ts';

test.each([
  'gh issue edit 312 --add-assignee @me',
  'gh issue close 312',
  'gh pr create',
  'gh pr merge',
  'gh pr ready',
  'gh pr close',
  'cd x && gh pr create --base y',
  'gh   pr    create',
  'GH_TOKEN=a gh pr merge 5',
  'echo done; gh issue close 1',
])('%j changes slices', (command) => expect(changesSlices(command)).toBe(true));

test.each(['gh issue view 312', 'gh pr list --state open', 'ghost issue edit 1', 'git push -u origin x', ''])('%j does not', (command) =>
  expect(changesSlices(command)).toBe(false),
);
