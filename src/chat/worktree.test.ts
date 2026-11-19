import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, test, vi } from 'vitest';
import { FakeGit } from './fake.ts';
import { ChatRefused } from './runner.ts';
import { countPorcelain } from './workspace.ts';
import { createWorktree, parseCount } from './worktree.ts';

test('parseCount reads the number rev-list --count printed, and 0 for anything else', () => {
  expect(parseCount('3\n')).toBe(3);
  expect(parseCount('0\n')).toBe(0);
  expect(parseCount('')).toBe(0);
  expect(parseCount('fatal')).toBe(0);
});

test('dirty is the number of lines git status --porcelain prints', () => {
  expect(countPorcelain('')).toBe(0);
  expect(countPorcelain(' M a.ts\n?? b.ts\nA  c.ts\n')).toBe(3);
});

test('a worktree the person cancels is refused as cancelled and not logged as a failure of git', async () => {
  const errors = vi.spyOn(console, 'error').mockImplementation(() => {});
  const folder = mkdtempSync(join(tmpdir(), 'wt-'));
  try {
    const git = new FakeGit();
    git.repos.set(folder, { head: 'main', branches: ['main'] });
    git.worktreePending = new Promise(() => {});
    const abort = new AbortController();
    const making = createWorktree(git, folder, { from: 'main', name: 'my-fix' }, abort.signal);
    await vi.waitFor(() => expect(git.calls.some((call) => call.args[0] === 'worktree' && call.args[1] === 'add')).toBe(true));
    abort.abort();
    await expect(making).rejects.toThrow(new ChatRefused('Creating the worktree was cancelled'));
    expect(errors.mock.calls.flat().join('\n')).not.toContain('git worktree add failed');
  } finally {
    errors.mockRestore();
    rmSync(folder, { recursive: true, force: true });
  }
});
