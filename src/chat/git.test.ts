import { expect, test, vi } from 'vitest';
import { realGit } from './git.ts';

// the binary `withGit` hands over, replaced for the test that checks it is the one started
const handed = vi.hoisted(() => ({ binary: undefined as string | undefined, failedWith: undefined as unknown }));
vi.mock('../execution/git-binary.ts', async (original) => {
  const real = await original<typeof import('../execution/git-binary.ts')>();
  const withGit = <T>(start: (binary: string) => Promise<T>) =>
    real.withGit(async (binary) => {
      try {
        return await start(handed.binary ?? binary);
      } catch (error) {
        handed.failedWith = (error as NodeJS.ErrnoException).code; // what the runner is told, so it can use another git
        throw error;
      }
    });
  return { ...real, withGit };
});

test('git is started with the binary the machine hands over, and one that is not there is a result, not a rejection', async () => {
  expect(await realGit.run('/', ['--version'])).toMatchObject({ ok: true, out: expect.stringMatching(/^git version /) });
  handed.binary = '/no/such/git';
  try {
    expect(await realGit.run('/', ['--version'])).toMatchObject({ ok: false, code: null });
    expect(handed.failedWith).toBe('ENOENT');
  } finally {
    handed.binary = undefined;
  }
});
