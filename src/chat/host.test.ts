import { mkdirSync, mkdtempSync, realpathSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { Config } from '../config/schema.ts';
import { connectControl } from '../terminal/cli/control-client.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { acquireLock } from '../storage/lock.ts';
import { FakeChatRunner, FakeGit } from './fake.ts';
import { HostBusy, startChatHost } from './host.ts';

let root: string;
let stops: (() => Promise<void>)[];
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'hs-')); // short: a socket path holds 103 bytes on macOS
  stops = [];
});
afterEach(async () => {
  for (const stop of stops) await stop();
  rmSync(root, { recursive: true, force: true });
});

const config = () => ({ root, logLevel: 'info' }) as Config;
async function host(clock = new FakeClock(), claude = new FakeChatRunner(), git = new FakeGit()) {
  const exit = vi.fn();
  const started = await startChatHost(config(), { installLogging: () => {}, clock, exit, signals: false, runners: { claude }, git, binaryFound: () => true });
  stops.push(started.stop);
  return { ...started, exit, clock };
}

test('the host makes its folder 0700 with a 0600 socket, a lock, chat.db with a sessions table, and answers list', async () => {
  await host();
  const chat = join(root, 'chat');
  expect(statSync(chat).mode & 0o777).toBe(0o700);
  expect(statSync(join(chat, 'chat.sock')).mode & 0o777).toBe(0o600);
  expect(statSync(join(chat, 'carrier.lock')).isFile()).toBe(true);
  const db = new Database(join(chat, 'chat.db'), { readonly: true });
  expect(db.prepare("select name from sqlite_master where name = 'sessions'").all()).toHaveLength(1);
  db.close();
  const client = await connectControl(join(chat, 'chat.sock'));
  expect(client.hello.protocol).toBe(1);
  expect(await client.request('list')).toEqual({ sessions: [] });
  client.close();
});

test('a second host on the same root is refused, and the lock is free again after stop', async () => {
  const first = await host();
  await expect(startChatHost(config(), { installLogging: () => {}, signals: false })).rejects.toThrow(HostBusy);
  await first.stop();
  const again = await host();
  expect(again.exit).not.toHaveBeenCalled();
});

test('the chat lock and the engine lock are held together on one root', async () => {
  await host();
  const engine = acquireLock(join(root, 'orchestrator'));
  expect(engine.ok).toBe(true);
  expect(acquireLock(join(root, 'chat')).ok).toBe(false); // still the host's
  if (engine.ok) engine.release();
});

test('the stop request ends the host: it exits 0, removes the socket and frees the lock', async () => {
  const { exit } = await host();
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  await client.request('stop');
  await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(0));
  const lock = acquireLock(join(root, 'chat'));
  expect(lock.ok).toBe(true);
  if (lock.ok) lock.release();
  expect(() => statSync(join(root, 'chat', 'chat.sock'))).toThrow();
});

test('the host exits a minute after its start, and a client connected keeps it up until it leaves', async () => {
  const { clock, exit } = await host();
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  await clock.advance(5 * 60_000);
  expect(exit).not.toHaveBeenCalled();
  client.close();
  // the leave reaches the host a moment after close(), so the minute is advanced until it has been armed
  await vi.waitFor(async () => {
    await clock.advance(60_000);
    expect(exit).toHaveBeenCalledWith(0);
  });
});

test('a client opens a conversation, sends, reads the events by cursor and closes it, all over the socket; the stop closes what is live', async () => {
  const claude = new FakeChatRunner();
  claude.setup = (c) => {
    c.reply = (text) => c.emit({ kind: 'assistant', text: `re: ${text}` }, { kind: 'turn_end', outcome: 'ok' });
  };
  const { exit } = await host(new FakeClock(), claude);
  const work = join(root, 'w');
  mkdirSync(work);
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  expect(client.hello.capabilities).toEqual(expect.arrayContaining(['agents', 'open', 'send', 'events', 'close', 'list']));
  expect(await client.request('agents')).toEqual([
    { name: 'claude', harness: 'claude', found: true },
    { name: 'codex', harness: 'codex', found: true },
  ]);
  await expect(client.request('open', { agent: 'claude', folder: join(root, 'chat') })).resolves.toBeDefined(); // the chat folder is the host's own, not a forbidden one
  await expect(client.request('open', { agent: 'claude', folder: join(root, 'repos') })).rejects.toThrow('does not exist');
  mkdirSync(join(root, 'repos'));
  await expect(client.request('open', { agent: 'claude', folder: join(root, 'repos') })).rejects.toThrow('inside Carrier');
  await expect(client.request('open', { agent: 'codex', folder: work })).rejects.toThrow('no chat runner for codex');
  const { session } = (await client.request('open', { agent: 'claude', folder: work })) as { session: { id: string } };
  await client.request('send', { sessionId: session.id, text: 'hi' });
  const reply = (await client.request('events', { sessionId: session.id, limit: 50 })) as any;
  expect(reply.events.map((e: any) => [e.kind, e.text])).toEqual([['user', 'hi'], ['assistant', 're: hi'], ['turn_end', undefined]]);
  expect(reply.session).toMatchObject({ id: session.id, title: 'hi', state: 'idle' });
  expect(((await client.request('list')) as any).sessions).toHaveLength(2);
  await expect(client.request('interrupt', { sessionId: session.id })).resolves.toEqual({}); // no turn is running
  await client.request('close', { sessionId: session.id });
  expect(claude.conversations.map((c) => c.closed)).toEqual([false, true]);
  await client.request('stop');
  await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(0));
  expect(claude.conversations.map((c) => c.closed)).toEqual([true, true]);
});

test('a new host over the same chat.db resumes a session of the one that ended, with the native id, and lists it as closed', async () => {
  const work = join(root, 'w');
  mkdirSync(work);
  const first = new FakeChatRunner();
  first.setup = (c) => {
    c.reply = (text) => {
      c.nativeId = 'native-7';
      c.emit({ kind: 'assistant', text: `re: ${text}` }, { kind: 'turn_end', outcome: 'ok' });
    };
  };
  const one = await host(new FakeClock(), first);
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  const { session } = (await client.request('open', { agent: 'claude', folder: work })) as { session: { id: string } };
  await client.request('send', { sessionId: session.id, text: 'the word is pineapple' });
  await client.request('stop');
  await vi.waitFor(() => expect(one.exit).toHaveBeenCalledWith(0));
  client.close();

  const second = new FakeChatRunner();
  await host(new FakeClock(), second);
  const again = await connectControl(join(root, 'chat', 'chat.sock'));
  expect(again.hello.capabilities).toContain('resume');
  expect(((await again.request('list')) as any).sessions).toMatchObject([{ id: session.id, live: false }]);
  await expect(again.request('resume', { sessionId: '00000000-0000-4000-8000-000000000000' })).rejects.toThrow('no such session');
  await again.request('resume', { sessionId: session.id });
  expect(second.opened[0]).toMatchObject({ resume: 'native-7', folder: expect.stringContaining('w') });
  const reply = (await again.request('events', { sessionId: session.id, limit: 50 })) as any;
  expect(reply.events.map((e: any) => e.kind)).toEqual(['user', 'assistant', 'turn_end']);
  again.close();
});

test('an approval is asked with the provider choices, survives the client leaving, and is answered by a client that comes back; refused ids and a second answer change nothing', async () => {
  const work = join(root, 'w');
  mkdirSync(work);
  const claude = new FakeChatRunner();
  claude.setup = (c) => {
    c.reply = () => c.emit({ kind: 'approval', approvalId: 'a1', tool: 'Bash', arg: 'touch x', choices: [{ id: 'allow', label: 'Allow', allow: true }, { id: 'deny', label: 'Deny', allow: false }] });
  };
  const { clock } = await host(new FakeClock(), claude);
  const path = join(root, 'chat', 'chat.sock');
  const first = await connectControl(path);
  expect(first.hello.capabilities).toContain('answer');
  const { session } = (await first.request('open', { agent: 'claude', folder: work })) as { session: { id: string } };
  await first.request('send', { sessionId: session.id, text: 'touch x' });
  first.close(); // the person leaves while it waits
  await clock.advance(10 * 60_000);
  expect(claude.conversations[0]!.closed).toBe(false);

  const again = await connectControl(path);
  await again.request('resume', { sessionId: session.id });
  const pending = (await again.request('events', { sessionId: session.id, limit: 50 })) as any;
  expect(pending.session.state).toBe('waiting_approval');
  expect(pending.approvals).toEqual([{ approvalId: 'a1', tool: 'Bash', arg: 'touch x', choices: expect.any(Array) }]);
  const answer = (approvalId: string, choiceId: string) => again.request('answer', { sessionId: session.id, approvalId, choiceId });
  await expect(answer('nope', 'deny')).rejects.toThrow('not pending');
  await expect(answer('a1', 'maybe')).rejects.toThrow('not one of the choices: allow, deny');
  expect(claude.conversations[0]!.answers).toEqual([]);
  await expect(answer('a1', 'deny')).resolves.toEqual({});
  await expect(answer('a1', 'deny')).rejects.toThrow('not pending');
  expect(claude.conversations[0]!.answers).toEqual([{ approvalId: 'a1', choiceId: 'deny' }]);
  const done = (await again.request('events', { sessionId: session.id, limit: 50 })) as any;
  expect(done.approvals).toEqual([]);
  expect(done.session.state).toBe('working');
  expect(done.events.map((e: any) => e.kind)).toEqual(['user', 'approval', 'approval_answered']);
  expect(done.events.at(-1)).toMatchObject({ approvalId: 'a1', choiceId: 'deny' });
  again.close();
});

test('workspace tells a client what a folder is, with the fake git, and refuses the folders open refuses', async () => {
  const git = new FakeGit();
  await host(new FakeClock(), new FakeChatRunner(), git);
  mkdirSync(join(root, 'repo'));
  const repo = realpathSync(join(root, 'repo'));
  const plain = join(root, 'plain');
  mkdirSync(plain);
  const fetched = join(root, 'FETCH_HEAD');
  writeFileSync(fetched, '');
  utimesSync(fetched, 1_700_000_000, 1_700_000_000);
  git.repos.set(repo, { head: 'feat/x', branches: ['main', 'feat/x'], remoteBranches: ['main', 'dev'], originHead: 'main', origin: 'git@github.com:acme/app.git', status: [' M a.ts', '?? b.ts'], fetchHead: fetched });
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  expect(client.hello.capabilities).toContain('workspace');
  expect(await client.request('workspace', { folder: repo })).toEqual({
    folder: repo,
    git: true,
    bare: false,
    linkedWorktree: false,
    repo: { owner: 'acme', name: 'app' },
    branch: 'feat/x',
    defaultBranch: 'main',
    dirty: 2,
    branches: [{ name: 'main', remote: false }, { name: 'feat/x', remote: false }, { name: 'origin/main', remote: true }, { name: 'origin/dev', remote: true }],
    fetchedAt: 1_700_000_000_000,
  });
  expect(await client.request('workspace', { folder: plain })).toEqual({ folder: realpathSync(plain), git: false, bare: false, linkedWorktree: false, repo: null, branch: null, defaultBranch: null, dirty: 0, branches: [], fetchedAt: null });
  const asked = git.calls.length;
  await expect(client.request('workspace', { folder: join(root, 'missing') })).rejects.toThrow('does not exist');
  await expect(client.request('workspace', { folder: 'relative' })).rejects.toThrow('absolute');
  writeFileSync(join(root, 'file'), '');
  await expect(client.request('workspace', { folder: join(root, 'file') })).rejects.toThrow('not a folder');
  mkdirSync(join(root, 'repos'));
  await expect(client.request('workspace', { folder: join(root, 'repos') })).rejects.toThrow('inside Carrier');
  expect(git.calls).toHaveLength(asked); // a refused folder never reaches git
  git.failures.set('rev-parse --is-bare-repository --git-dir --git-common-dir --git-path FETCH_HEAD', { ok: false, code: null, stderr: 'git took too long' });
  await expect(client.request('workspace', { folder: repo })).rejects.toThrow('Git could not read that folder');
  client.close();
});

test('fetch runs git fetch origin --prune with a 60 second limit, answers the refreshed workspace and never tells what git said', async () => {
  const git = new FakeGit();
  await host(new FakeClock(), new FakeChatRunner(), git);
  mkdirSync(join(root, 'repo'));
  const repo = realpathSync(join(root, 'repo'));
  const fetched = join(root, 'FETCH_HEAD');
  writeFileSync(fetched, '');
  utimesSync(fetched, 1_700_000_000, 1_700_000_000);
  git.repos.set(repo, { head: 'main', branches: ['main'], remoteBranches: ['main'], origin: 'git@github.com:acme/app.git', fetchHead: fetched });
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  expect(client.hello.capabilities).toContain('fetch');
  const info = (await client.request('fetch', { folder: repo })) as { fetchedAt: number; branches: unknown[] };
  expect(info).toMatchObject({ folder: repo, git: true, fetchedAt: 1_700_000_000_000 });
  expect(git.calls.filter((call) => call.args[0] === 'fetch')).toEqual([{ folder: repo, args: ['fetch', 'origin', '--prune'], timeoutMs: 60_000 }]);

  const failure = 'fatal: unable to access https://user:ghp_secret@github.com/acme/app.git/';
  git.failures.set('fetch origin --prune', { ok: false, code: 128, stderr: failure });
  const failed = await client.request('fetch', { folder: repo }).catch((error: Error) => error.message);
  expect(failed).toBe('The fetch of origin failed');
  git.failures.set('fetch origin --prune', { ok: false, code: null, timedOut: true, stderr: 'git took too long' });
  await expect(client.request('fetch', { folder: repo })).rejects.toThrow('The fetch took too long and was stopped');

  git.repos.set(repo, { head: 'main', branches: ['main'] });
  git.failures.clear();
  await expect(client.request('fetch', { folder: repo })).rejects.toThrow('no origin remote');
  const plain = join(root, 'plain');
  mkdirSync(plain);
  await expect(client.request('fetch', { folder: plain })).rejects.toThrow('not a git repository');
  await expect(client.request('fetch', { folder: join(root, 'missing') })).rejects.toThrow('does not exist');
  client.close();
});

test('suggestName and checkName answer a free name, say why a name is invalid or taken in each of the three places, and refuse what is not a repository', async () => {
  vi.stubEnv('CARRIER_HOME', join(root, 'home'));
  stops.push(async () => void vi.unstubAllEnvs());
  const git = new FakeGit();
  await host(new FakeClock(), new FakeChatRunner(), git);
  mkdirSync(join(root, 'repo'));
  const repo = realpathSync(join(root, 'repo'));
  git.repos.set(repo, { head: 'main', branches: ['main', 'carrier/local-one'], remoteBranches: ['main', 'carrier/remote-one'], origin: 'git@github.com:acme/app.git' });
  mkdirSync(join(root, 'home', 'chat', 'worktrees', 'acme', 'app', 'folder-one'), { recursive: true });
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  expect(client.hello.capabilities).toEqual(expect.arrayContaining(['suggestName', 'checkName']));

  const suggested = (await client.request('suggestName', { folder: repo })) as { name: string };
  expect(suggested.name).toMatch(/^[a-z]+-[a-z]+-[a-z]+$/);
  expect(await client.request('checkName', { folder: repo, name: suggested.name })).toEqual({ valid: true, free: true });
  expect(await client.request('checkName', { folder: repo, name: 'fresh-name' })).toEqual({ valid: true, free: true });
  expect(await client.request('checkName', { folder: repo, name: 'local-one' })).toEqual({ valid: true, free: false, reason: 'A branch called carrier/local-one already exists' });
  expect(await client.request('checkName', { folder: repo, name: 'remote-one' })).toEqual({ valid: true, free: false, reason: 'The remote already has a branch called carrier/remote-one' });
  expect(await client.request('checkName', { folder: repo, name: 'folder-one' })).toEqual({ valid: true, free: false, reason: 'A folder for that worktree already exists' });
  expect(await client.request('checkName', { folder: repo, name: 'Bad Name' })).toMatchObject({ valid: false, free: false, reason: expect.stringContaining('lowercase') });
  expect(await client.request('checkName', { folder: repo, name: 'a..b' })).toMatchObject({ valid: false, free: false, reason: expect.stringContaining('two dots') });
  expect(await client.request('checkName', { folder: repo, name: 'x'.repeat(61) })).toMatchObject({ valid: false });

  const plain = join(root, 'plain');
  mkdirSync(plain);
  git.repos.set(join(root, 'bare'), { head: null, branches: [], bare: true });
  mkdirSync(join(root, 'bare'));
  for (const folder of [plain, realpathSync(join(root, 'bare'))]) {
    await expect(client.request('suggestName', { folder })).rejects.toThrow('Worktrees need a git repository');
    await expect(client.request('checkName', { folder, name: 'fine' })).rejects.toThrow('Worktrees need a git repository');
  }
  await expect(client.request('suggestName', { folder: join(root, 'missing') })).rejects.toThrow('does not exist');
  client.close();
});
