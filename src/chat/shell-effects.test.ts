import { expect, test } from 'vitest';
import { githubWorkOf } from './shell-effects.ts';

const NONE = { find: false, states: false };
const BOTH = { find: true, states: true };

test('a push asks for the pull request and its checks, with the options git takes before it and inside a longer command', () => {
  for (const command of ['git push', 'git push -u origin fix/x', 'git -C /work/app push', 'git -c core.editor=true push origin HEAD', 'git --no-pager push', 'cd app && git commit -qm x && git push', '/usr/bin/git push', 'bash -lc "git push origin main"', 'git add . ; git push']) {
    expect(githubWorkOf([command]), command).toEqual(BOTH);
  }
});

test('a commit, an add, a status or a diff ask GitHub for nothing', () => {
  for (const command of ['git commit -m "push the button"', 'git add -A', 'git status', 'git diff --stat', 'git log --grep push', 'git stash', 'git pull --rebase', 'git merge main', 'pnpm test', 'ls', 'echo pushed', 'gh issue list', 'gh pr view 12', 'gh pr list', 'gh pr diff 12', 'gh pr checks 12', 'github push', 'digit push']) {
    expect(githubWorkOf([command]), command).toEqual(NONE);
  }
});

test('moving to another branch or opening a pull request looks for the pull request, and does not ask for the state of the one it has', () => {
  for (const command of ['git checkout -b fix/x', 'git switch -c fix/x', 'git -C /w switch main', 'gh pr create --draft --title x', 'gh pr checkout 12', 'gh pr co 12']) {
    expect(githubWorkOf([command]), command).toEqual({ find: true, states: false });
  }
});

test('merging, closing, readying or reviewing a pull request, and running checks again, ask for its state and look for no other', () => {
  for (const command of ['gh pr merge 12 --merge', 'gh pr close 12', 'gh pr ready', 'gh pr reopen 12', 'gh pr review 12 --approve', 'gh run rerun 99', 'gh workflow run ci.yml']) {
    expect(githubWorkOf([command]), command).toEqual({ find: false, states: true });
  }
});

test('the commands of a turn add up: what one asks for is not taken back by another', () => {
  expect(githubWorkOf(['git commit -m x', 'gh pr create', 'gh pr merge 3'])).toEqual(BOTH);
  expect(githubWorkOf([])).toEqual(NONE);
  expect(githubWorkOf(['git status', 'pnpm test'])).toEqual(NONE);
});
