import { chmodSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import { AuthError, GitHubUnavailable } from '../orchestration/github.ts';
import { GhGitHub } from './github.ts';

// Stands in for `agent-forge`: logs its argv and answers with the first scripted reply whose `match`
// is contained in the joined arguments. No shell involved anywhere.
const fakeForge = `#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const dir = path.dirname(process.argv[1]);
const args = process.argv.slice(2);
fs.appendFileSync(path.join(dir, 'calls.jsonl'), JSON.stringify({ args, cwd: process.cwd() }) + '\\n');
const replies = JSON.parse(fs.readFileSync(path.join(dir, 'replies.json'), 'utf8'));
const reply = replies.find((r) => args.join(' ').includes(r.match)) ?? { stderr: 'no scripted reply', exit: 9 };
process.stderr.write(reply.stderr ?? '');
setTimeout(() => { process.stdout.write(reply.stdout ?? ''); process.exit(reply.exit ?? 0); }, reply.sleepMs ?? 0);
`;

type Reply = { match: string; stdout?: string; stderr?: string; exit?: number; sleepMs?: number };

const http = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  `HTTP/2.0 ${status} X\r\n${Object.entries({ 'Content-Type': 'application/json', ...headers })
    .map(([k, v]) => `${k}: ${v}`)
    .join('\r\n')}\r\n\r\n${JSON.stringify(body)}`;
const ok = (body: unknown) => ({ stdout: http(200, body) });
const failure = (status: number, body: unknown, headers?: Record<string, string>) => ({ stdout: http(status, body, headers), exit: 1 });

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-gh-'));
  writeFileSync(join(dir, 'fake-forge'), fakeForge);
  chmodSync(join(dir, 'fake-forge'), 0o755);
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

function setup(replies: Reply[], timeoutMs = 10_000) {
  writeFileSync(join(dir, 'replies.json'), JSON.stringify(replies));
  const github = new GhGitHub({
    profile: { kind: 'forge', agent: 'bot' },
    cwd: () => dir,
    timeoutMs,
    executable: join(dir, 'fake-forge'),
  });
  const calls = () =>
    readFileSync(join(dir, 'calls.jsonl'), 'utf8').trim().split('\n').map((line) => JSON.parse(line) as { args: string[]; cwd: string });
  return { github, calls };
}

const repo = 'AshuLab/demo';

describe('invocation', () => {
  test('runs `agent-forge gh <agent> api` with separated argv in the given cwd; hostile arguments arrive literally', async () => {
    const { github, calls } = setup([{ match: 'POST', stdout: http(200, []) }, { match: '/labels/', stdout: 'HTTP/2.0 204 No Content\r\nX-A: b\r\n\r\n' }]);
    await github.setLabels(repo, 7, { add: ['x; rm -rf /'], remove: ['$(touch pwned)'] });
    const [post, del] = calls();
    expect(post?.args).toEqual(['gh', 'bot', 'api', '-i', '-X', 'POST', 'repos/AshuLab/demo/issues/7/labels', '-f', 'labels[]=x; rm -rf /']);
    expect(del?.args.at(-1)).toBe('repos/AshuLab/demo/issues/7/labels/%24(touch%20pwned)');
    expect(post?.cwd).toBe(realpathSync(dir));
  });

  test('a gh profile runs gh directly, without Forge arguments', async () => {
    writeFileSync(join(dir, 'replies.json'), JSON.stringify([{ match: 'labels', stdout: http(200, []) }]));
    const github = new GhGitHub({ profile: { kind: 'gh' }, cwd: () => dir, timeoutMs: 5000, executable: join(dir, 'fake-forge') });
    await github.listLabels(repo);
    expect(JSON.parse(readFileSync(join(dir, 'calls.jsonl'), 'utf8').trim()).args.slice(0, 2)).toEqual(['api', '-i']);
  });

  test('a repo that is not owner/name is refused before running anything', async () => {
    const { github } = setup([]);
    await expect(github.getIssue('a/b; rm -rf /', 1)).rejects.toThrow('invalid repo');
  });
});

describe('responses', () => {
  test('a malformed response throws, it is never an empty list', async () => {
    const { github } = setup([{ match: 'issues', ...ok({ not: 'a list' }) }]);
    await expect(github.listReadyEpics(repo)).rejects.toThrow();
    const wrongShape = setup([{ match: 'issues', ...ok([{ number: 'x', title: 1 }]) }]);
    await expect(wrongShape.github.listReadyEpics(repo)).rejects.toThrow();
    const notJson = setup([{ match: 'issues', stdout: 'HTTP/2.0 200 OK\r\n\r\n<html>' }]);
    await expect(notJson.github.listReadyEpics(repo)).rejects.toThrow();
    const garbage = setup([{ match: 'issues', stdout: 'hello' }]);
    await expect(garbage.github.listReadyEpics(repo)).rejects.toThrow();
  });

  test('listReadyEpics returns every page and skips pull requests', async () => {
    const row = (number: number) => ({ number, title: `epic ${number}` });
    const page1 = Array.from({ length: 100 }, (_, i) => row(i + 1));
    const page2 = [...Array.from({ length: 99 }, (_, i) => row(i + 101)), { ...row(999), pull_request: {} }];
    const page3 = [row(201)];
    const { github, calls } = setup([
      { match: '&page=1', ...ok(page1) },
      { match: '&page=2', ...ok(page2) },
      { match: '&page=3', ...ok(page3) },
    ]);
    const epics = await github.listReadyEpics(repo);
    expect(epics).toHaveLength(200);
    expect(epics.map((e) => e.issue)).not.toContain(999);
    expect(calls()).toHaveLength(3);
    expect(calls()[0]?.args.at(-1)).toContain('labels=solve%3Aepic%3Aready');
  });

  test('getIssue, getPullRequest and findPullRequest map the API shape', async () => {
    const pull = (number: number, body: string | null, merged_at: string | null, state = 'closed') => ({ number, state, merged_at, body, head: { sha: 'a'.repeat(40), ref: 'feat/demo/epic' } });
    const { github } = setup([
      { match: 'issues/5', ...ok({ state: 'open', labels: [{ name: 'solve:epic:ready' }] }) },
      { match: 'pulls/10', ...ok(pull(10, null, '2026-01-01T00:00:00Z')) },
      { match: 'pulls/11', ...failure(404, { message: 'Not Found' }) },
      { match: 'pulls?', ...ok([pull(30, 'Closes #53', null, 'open'), pull(20, 'Fixes AshuLab/demo#5 and more', '2026-01-01T00:00:00Z')]) },
    ]);
    expect(await github.getIssue(repo, 5)).toEqual({ state: 'open', labels: ['solve:epic:ready'] });
    expect(await github.getPullRequest(repo, 10)).toEqual({ state: 'merged', body: '', headSha: 'a'.repeat(40), headRef: 'feat/demo/epic' });
    expect(await github.getPullRequest(repo, 11)).toBeNull();
    expect(await github.findPullRequest(repo, 5)).toEqual({ number: 20, state: 'merged', headSha: 'a'.repeat(40) });
    expect(await github.findPullRequest(repo, 6)).toBeNull();
  });

  test('labels: listing pages, removing a label the issue lacks and re-creating an existing one are no-ops', async () => {
    const { github } = setup([
      { match: 'labels?', ...ok([{ name: 'a' }]) },
      { match: 'DELETE', ...failure(404, { message: 'Label does not exist' }) },
      { match: 'name=taken', ...failure(422, { message: 'Validation Failed', errors: [{ code: 'already_exists' }] }) },
    ]);
    expect(await github.listLabels(repo)).toEqual(['a']);
    await github.setLabels(repo, 1, { add: [], remove: ['gone'] });
    await github.createLabel(repo, 'taken');
  });

  test('other HTTP errors (404 on an issue, 422) throw a plain error, not Unavailable', async () => {
    const { github } = setup([{ match: 'issues/1', ...failure(404, { message: 'Not Found' }) }]);
    const error = await github.getIssue(repo, 1).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(Error);
    expect(error).not.toBeInstanceOf(GitHubUnavailable);
    expect(error).not.toBeInstanceOf(AuthError);
  });
});

describe('failures', () => {
  const unavailable = async (reply: Omit<Reply, 'match'>) => {
    const { github } = setup([{ match: 'issues/1', ...reply }]);
    const error = await github.getIssue(repo, 1).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(GitHubUnavailable);
    return (error as GitHubUnavailable).retryAfterMs;
  };

  test('rate limit: Retry-After and the reset time become retryAfterMs', async () => {
    expect(await unavailable(failure(429, { message: 'slow down' }, { 'Retry-After': '60' }))).toBe(60_000);
    expect(await unavailable(failure(403, { message: 'You have exceeded a secondary rate limit' }, { 'retry-after': '30' }))).toBe(30_000);
    const reset = Math.floor(Date.now() / 1000) + 120;
    const wait = await unavailable(failure(403, { message: 'API rate limit exceeded' }, { 'X-RateLimit-Remaining': '0', 'X-RateLimit-Reset': String(reset) }));
    expect(wait).toBeGreaterThan(100_000);
    expect(wait).toBeLessThanOrEqual(120_000);
    expect(await unavailable(failure(403, { message: 'API rate limit exceeded' }))).toBeUndefined();
  });

  test('5xx and network errors are Unavailable', async () => {
    expect(await unavailable(failure(502, { message: 'bad gateway' }))).toBeUndefined();
    expect(await unavailable(failure(503, {}, { 'Retry-After': '5' }))).toBe(5000);
    expect(await unavailable({ stderr: 'error connecting to api.github.com\ncheck your internet connection', exit: 1 })).toBeUndefined();
    expect(await unavailable({ stderr: 'Get "https://api.github.com": dial tcp: lookup api.github.com: no such host', exit: 1 })).toBeUndefined();
  });

  test('a 403 that is not a rate limit is not Unavailable', async () => {
    const { github } = setup([{ match: 'issues/1', ...failure(403, { message: 'Resource not accessible by integration' }) }]);
    const error = await github.getIssue(repo, 1).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(Error);
    expect(error).not.toBeInstanceOf(GitHubUnavailable);
  });

  test.each([
    ['Forge: unknown profile', '│\n■  Agent not found: no-such-agent'],
    ['Forge: missing key', '│\n■  Private key for "bot" not found or unreadable: /x/key.pem'],
    ['Forge: wrong key', '│\n■  GitHub API /app/installations: 401 A JSON web token could not be decoded — the App JWT was rejected.'],
    ['Forge: no installations', '│\n■  GitHub App 1 has no installations'],
    ['gh: revoked token', 'gh: Bad credentials (HTTP 401)'],
  ])('auth error from stderr: %s', async (_name, stderr) => {
    const { github } = setup([{ match: 'issues/1', stderr, exit: 1 }]);
    await expect(github.getIssue(repo, 1)).rejects.toBeInstanceOf(AuthError);
  });

  test('HTTP 401 with a body is an AuthError', async () => {
    const { github } = setup([{ match: 'issues/1', ...failure(401, { message: 'Bad credentials' }) }]);
    await expect(github.getIssue(repo, 1)).rejects.toBeInstanceOf(AuthError);
  });

  test('Forge cwd and usage errors are plain errors, not auth', async () => {
    for (const stderr of ['■  GitHub App 1 is installed on 2 accounts (AshuLab, vemec). Launch from inside a repo under one of them.', '■  Usage: agent-forge gh <agent-name> <gh args...>']) {
      const { github } = setup([{ match: 'issues/1', stderr, exit: 1 }]);
      const error = await github.getIssue(repo, 1).catch((e: unknown) => e);
      expect(error).toBeInstanceOf(Error);
      expect(error).not.toBeInstanceOf(AuthError);
      expect(error).not.toBeInstanceOf(GitHubUnavailable);
    }
  });

  test('a call that outlives the timeout is cut and is Unavailable', async () => {
    const { github } = setup([{ match: 'issues/1', ...ok({}), sleepMs: 5000 }], 300);
    const started = Date.now();
    await expect(github.getIssue(repo, 1)).rejects.toBeInstanceOf(GitHubUnavailable);
    expect(Date.now() - started).toBeLessThan(3000);
  });
});
