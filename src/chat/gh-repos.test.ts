import { beforeEach, expect, test, vi } from 'vitest';

const execFile = vi.hoisted(() => vi.fn());
vi.mock('node:child_process', () => ({ execFile }));

const { ghRepos, ghBranches } = await import('./projects.ts');

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

test('the branches of a repository are the default one and the first hundred, with hasMore when that page was full', async () => {
  const names = Array.from({ length: 100 }, (_, i) => `b${i}`);
  execFile.mockImplementation((_cmd: string, args: string[], _opts: object, done: (error: null, out: { stdout: string }) => void) => done(null, { stdout: args.some((arg) => arg.includes('/branches')) ? `${names.join('\n')}\n` : 'trunk\n' }));
  expect(await ghBranches('acme/app', 1000)).toEqual({ default: 'trunk', branches: names, hasMore: true });
  const asked = execFile.mock.calls.map((call) => (call[1] as string[]).join(' '));
  expect(asked).toEqual(expect.arrayContaining([expect.stringContaining('api repos/acme/app --jq'), expect.stringContaining('api repos/acme/app/branches?per_page=100 --jq')]));
});
