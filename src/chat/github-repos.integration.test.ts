import { describe, expect, test } from 'vitest';
import { ghLogin, ghRepos } from './projects.ts';

// The real `gh`, with the person's own login: the chat's listing returns the private repositories and the ones of an organisation.
// It only reads (two `gh api` calls per page). It only runs when this is set explicitly, by someone whose login has at least one
// private repository and one that belongs to an organisation or another user:
//   CARRIER_IT_GH_REPOS=1
// No token is read or printed.
const enabled = process.env.CARRIER_IT_GH_REPOS === '1';
if (!enabled) console.warn('GitHub repos listing integration test skipped: set CARRIER_IT_GH_REPOS=1 to run it.');

describe.skipIf(!enabled)('the chat host lists repositories with the real gh', () => {
  test(
    'private and organisation repositories come back, thirty at most a page, newest push first',
    async () => {
      const login = await ghLogin(30_000);
      expect(login).not.toBe('');
      const repos = [];
      for (let page = 1; page <= 5; page++) {
        const listed = await ghRepos(page, 30_000);
        expect(listed.repos.length).toBeLessThanOrEqual(30);
        repos.push(...listed.repos);
        if (listed.hasMore === false) break;
      }
      expect(repos.some((repo) => repo.private)).toBe(true);
      expect(repos.some((repo) => repo.name.split('/')[0]!.toLowerCase() !== login.toLowerCase())).toBe(true);
      const pushed = repos.flatMap((repo) => (repo.pushedAt === null ? [] : [repo.pushedAt]));
      expect(pushed).toEqual([...pushed].sort().reverse());
    },
    120_000,
  );
});
