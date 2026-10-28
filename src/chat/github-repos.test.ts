import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { Config } from '../config/schema.ts';
import type { AvailableRepo } from '../integrations/available-repos.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { connectControl } from '../terminal/cli/control-client.ts';
import { FakeChatRunner } from './fake.ts';
import { startChatHost } from './host.ts';
import { ghRefusal } from './projects.ts';
import { ChatRefused } from './runner.ts';

// The host's githubRepos request through its socket, with a fake listing in place of `gh`.
let root: string;
let stop: (() => Promise<void>) | undefined;
let asked: number[];
let pages: Record<number, { repos: AvailableRepo[]; hasMore: boolean }>;
let failure: Error | undefined;
let logins: number;
const repo = (name: string, isPrivate = false): AvailableRepo => ({ name, private: isPrivate, pushedAt: '2026-10-20T10:00:00Z' });

beforeEach(async () => {
  root = mkdtempSync(join(tmpdir(), 'gr-')); // short: a socket path holds 103 bytes on macOS
  asked = [];
  logins = 0;
  failure = undefined;
  pages = { 1: { repos: [repo('acme/app', true), repo('org/lib')], hasMore: true }, 2: { repos: [repo('me/old')], hasMore: false } };
  const github = {
    repos: async (page: number) => {
      asked.push(page);
      if (failure !== undefined) throw failure;
      return pages[page] ?? { repos: [], hasMore: false };
    },
    login: async () => {
      logins++;
      return 'vemec';
    },
  };
  const started = await startChatHost({ root, logLevel: 'info' } as Config, { installLogging: () => {}, clock: new FakeClock(), exit: vi.fn(), signals: false, runners: { claude: new FakeChatRunner() }, github, binaryFound: () => true });
  stop = started.stop;
});
afterEach(async () => {
  await stop?.();
  rmSync(root, { recursive: true, force: true });
});
const connect = () => connectControl(join(root, 'chat', 'chat.sock'));

test('the hello lists githubRepos, and page 1 answers the repositories, hasMore and the login', async () => {
  const client = await connect();
  expect(client.hello.capabilities).toContain('githubRepos');
  expect(await client.request('githubRepos', { page: 1 })).toEqual({ repos: pages[1]!.repos, hasMore: true, login: 'vemec' });
  client.close();
});

test('a later page answers its repositories and hasMore, and no login', async () => {
  const client = await connect();
  expect(await client.request('githubRepos', { page: 2 })).toEqual({ repos: pages[2]!.repos, hasMore: false });
  expect(asked).toEqual([2]);
  expect(logins).toBe(0);
  client.close();
});

test('a page that is not an integer from 1 to 100 never reaches the listing', async () => {
  const client = await connect();
  for (const page of [0, 101, 1.5, '1', null]) await expect(client.request('githubRepos', { page } as never)).rejects.toThrow('invalid request');
  expect(asked).toEqual([]);
  client.close();
});

test('gh missing, signed out, offline or slow comes back as a refusal with its own sentence', async () => {
  const client = await connect();
  failure = new ChatRefused('gh is not signed in to GitHub; run "gh auth login"');
  await expect(client.request('githubRepos', { page: 1 })).rejects.toThrow('gh is not signed in to GitHub; run "gh auth login"');
  await expect(client.request('githubRepos', { page: 2 })).rejects.toThrow('gh is not signed in to GitHub; run "gh auth login"');
  failure = new Error('boom');
  await expect(client.request('githubRepos', { page: 2 })).rejects.toThrow('internal error');
  client.close();
});

test.each([
  ['gh missing', { code: 'ENOENT' }, 'The GitHub CLI (gh) is not installed'],
  ['signed out', { code: 4, stderr: 'To get started with GitHub CLI, please run:  gh auth login' }, 'gh is not signed in to GitHub; run "gh auth login"'],
  ['a rejected token', { code: 1, stderr: 'gh: Bad credentials (HTTP 401)' }, 'gh is not signed in to GitHub; run "gh auth login"'],
  ['offline', { code: 1, stderr: 'error connecting to api.github.com' }, 'GitHub could not be reached; check the network connection'],
  ['too slow', { killed: true, code: null }, 'GitHub took too long to answer'],
  ['anything else', { code: 1, stderr: 'gh: Server Error with a token ghp_secrettoken' }, 'GitHub did not answer; check "gh auth status"'],
])('a failed gh call (%s) is told in words and never with what gh printed', (_name, error, sentence) => {
  const refusal = ghRefusal(error, 'repos');
  expect(refusal).toBeInstanceOf(ChatRefused);
  expect(refusal.message).toBe(sentence);
});
