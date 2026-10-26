import { expect, test } from 'vitest';
import { ghReposArgs, parseRepos } from './available-repos.ts';

test('ghReposArgs asks for one page of 30 and prints the raw count first', () => {
  const args = ghReposArgs(3);
  expect(args[1]).toBe('user/repos?affiliation=owner,organization_member&sort=pushed&per_page=30&page=3');
  expect(args[3]).toMatch(/^\(length \| tostring\), \(\.\[\] \| select\(\.archived or \.disabled \| not\) \| select\(\.permissions\.push\)/);
});

test('a full raw page has more, even when the filter left fewer repos', () => {
  const out = ['30', 'AshuLab/carrier\ttrue\t2026-10-20T10:00:00Z', 'vemec/encaja\tfalse\t'].join('\n');
  expect(parseRepos(out)).toEqual({
    repos: [
      { name: 'AshuLab/carrier', private: true, pushedAt: '2026-10-20T10:00:00Z' },
      { name: 'vemec/encaja', private: false, pushedAt: null },
    ],
    hasMore: true,
  });
});

test('a page whose repos were all filtered out is empty and keeps hasMore', () => {
  expect(parseRepos('30\n')).toEqual({ repos: [], hasMore: true });
  expect(parseRepos('30')).toEqual({ repos: [], hasMore: true });
});

test('a short raw page is the last one', () => {
  expect(parseRepos('29\nAshuLab/carrier\ttrue\t').hasMore).toBe(false);
  expect(parseRepos('0\n')).toEqual({ repos: [], hasMore: false });
});

test('a name that is not owner/name is dropped', () => {
  expect(parseRepos('2\nnot a repo\ttrue\t\nAshuLab/carrier\ttrue\t').repos.map((r) => r.name)).toEqual(['AshuLab/carrier']);
});
