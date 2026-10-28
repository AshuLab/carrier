import { beforeEach, expect, test, vi } from 'vitest';

const execFile = vi.hoisted(() => vi.fn());
vi.mock('node:child_process', () => ({ execFile }));

const { ghRepos } = await import('./projects.ts');

beforeEach(() => {
  execFile.mockReset();
  execFile.mockImplementation((_cmd: string, _args: string[], _opts: object, done: (error: null, out: { stdout: string }) => void) => done(null, { stdout: '0\n' }));
});

test('the chat lists every repository the login can read: collaborator included and no filter on push permission', async () => {
  await ghRepos(1, 1000);
  const args = execFile.mock.calls[0]![1] as string[];
  expect(args.join(' ')).toContain('affiliation=owner,collaborator,organization_member');
  expect(args.join(' ')).not.toContain('permissions.push');
});
