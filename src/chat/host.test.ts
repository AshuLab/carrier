import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
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

/** A host with a fake git, a base repository acme/app and CARRIER_HOME under the temporary root. */
async function worktreeHost() {
  vi.stubEnv('CARRIER_HOME', join(root, 'home'));
  stops.push(async () => void vi.unstubAllEnvs());
  const git = new FakeGit();
  const claude = new FakeChatRunner();
  await host(new FakeClock(), claude, git);
  mkdirSync(join(root, 'repo'));
  const repo = realpathSync(join(root, 'repo'));
  git.repos.set(repo, { head: 'feat/x', branches: ['main', 'feat/x'], remoteBranches: ['main', 'dev'], origin: 'git@github.com:acme/app.git', status: [' M a.ts'] });
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  const worktrees = join(root, 'home', 'chat', 'worktrees');
  return { git, claude, client, repo, worktrees, base: git.repos.get(repo)! };
}
const worktreeAdds = (git: FakeGit) => git.calls.filter((call) => call.args[0] === 'worktree' && call.args[1] === 'add');

test('open with a worktree makes it under Carrier home on carrier/<name> from a local and from a remote branch, runs the session in it, leaves the base alone and lists the workspace', async () => {
  const { git, claude, client, repo, worktrees, base } = await worktreeHost();
  expect(client.hello.capabilities).toContain('open');
  const local = (await client.request('open', { agent: 'claude', folder: repo, worktree: { from: 'main', name: 'alpha' } })) as { session: any };
  const path = join(worktrees, 'acme', 'app', 'alpha');
  expect(local.session).toMatchObject({ folder: path, workspace: { kind: 'worktree', branch: 'carrier/alpha', from: 'main', base: repo, path } });
  expect(statSync(path).isDirectory()).toBe(true);
  expect(claude.opened[0]).toMatchObject({ folder: path });
  expect(worktreeAdds(git)).toEqual([{ folder: repo, args: ['worktree', 'add', '--no-track', '-b', 'carrier/alpha', path, 'refs/heads/main'], timeoutMs: 60_000 }]);

  const remote = (await client.request('open', { agent: 'claude', folder: repo, worktree: { from: 'origin/dev' } })) as { session: any };
  expect(remote.session.workspace).toMatchObject({ kind: 'worktree', from: 'origin/dev', base: repo });
  expect(remote.session.workspace.branch).toMatch(/^carrier\/[a-z]+-[a-z]+-[a-z]+$/); // a generated name
  expect(remote.session.workspace.path).toBe(join(worktrees, 'acme', 'app', remote.session.workspace.branch.slice('carrier/'.length)));
  expect(worktreeAdds(git)[1]!.args.at(-1)).toBe('refs/remotes/origin/dev');

  const plain = (await client.request('open', { agent: 'claude', folder: repo })) as { session: any };
  expect(plain.session).toMatchObject({ folder: repo, workspace: { kind: 'folder' } });
  const listed = ((await client.request('list')) as any).sessions;
  expect(listed.find((s: any) => s.id === local.session.id).workspace).toEqual(local.session.workspace);
  expect(listed.find((s: any) => s.id === plain.session.id).workspace).toEqual({ kind: 'folder' });
  const events = (await client.request('events', { sessionId: local.session.id, limit: 10 })) as any;
  expect(events.session.workspace).toEqual(local.session.workspace);

  // the base folder: same branch checked out, same changes, and git was only ever asked to add (never checkout, stash, commit, reset)
  expect(base).toMatchObject({ head: 'feat/x', status: [' M a.ts'] });
  const verbs = new Set(git.calls.map((call) => call.args.find((arg) => arg !== '--no-optional-locks')));
  expect([...verbs].filter((verb) => ['checkout', 'switch', 'stash', 'commit', 'reset', 'merge', 'clean'].includes(verb!))).toEqual([]);
  expect(git.calls.every((call) => call.folder === repo)).toBe(true);

  // a repository without a GitHub origin goes under local/<folder name>
  mkdirSync(join(root, 'solo'));
  const solo = realpathSync(join(root, 'solo'));
  git.repos.set(solo, { head: 'main', branches: ['main'] });
  const opened = (await client.request('open', { agent: 'claude', folder: solo, worktree: { from: 'main', name: 'beta' } })) as { session: any };
  expect(opened.session.workspace.path).toBe(join(worktrees, 'local', 'solo', 'beta'));
  client.close();
});

test('open with a worktree refuses a folder that is not a repository, a bare one, an unlisted start, and an invalid or taken name, and leaves nothing', async () => {
  const { git, claude, client, repo, worktrees } = await worktreeHost();
  mkdirSync(join(worktrees, 'acme', 'app', 'folder-one'), { recursive: true });
  git.repos.set(repo, { head: 'main', branches: ['main', 'carrier/local-one'], remoteBranches: ['main', 'carrier/remote-one'], origin: 'git@github.com:acme/app.git' });
  const plain = join(root, 'plain');
  mkdirSync(plain);
  mkdirSync(join(root, 'bare'));
  git.repos.set(realpathSync(join(root, 'bare')), { head: null, branches: [], bare: true });
  const open = (folder: string, worktree: { from: string; name?: string }) => client.request('open', { agent: 'claude', folder, worktree });
  await expect(open(plain, { from: 'main' })).rejects.toThrow('Worktrees need a git repository');
  await expect(open(join(root, 'bare'), { from: 'main' })).rejects.toThrow('this one is bare');
  await expect(open(repo, { from: 'nope' })).rejects.toThrow('not one this repository lists');
  await expect(open(repo, { from: 'origin/HEAD' })).rejects.toThrow('not one this repository lists');
  await expect(open(repo, { from: '--orphan' })).rejects.toThrow('not one this repository lists');
  await expect(open(repo, { from: 'main', name: 'Bad Name' })).rejects.toThrow('lowercase');
  await expect(open(repo, { from: 'main', name: '--force' })).rejects.toThrow('must start with');
  await expect(open(repo, { from: 'main', name: 'a/../escape' })).rejects.toThrow('may only have');
  await expect(open(repo, { from: 'main', name: 'local-one' })).rejects.toThrow('A branch called carrier/local-one already exists');
  await expect(open(repo, { from: 'main', name: 'remote-one' })).rejects.toThrow('The remote already has a branch called carrier/remote-one');
  await expect(open(repo, { from: 'main', name: 'folder-one' })).rejects.toThrow('A folder for that worktree already exists');
  await expect(client.request('open', { agent: 'claude', folder: repo, worktree: { from: 'main', extra: 1 } })).rejects.toThrow('invalid request');
  expect(worktreeAdds(git)).toEqual([]);
  expect(claude.opened).toEqual([]);
  expect(((await client.request('list')) as any).sessions).toEqual([]);
  client.close();
});

test('a git failure while adding leaves no worktree, no branch and no session, and says so in words without what git said', async () => {
  const { git, claude, client, repo, worktrees, base } = await worktreeHost();
  const path = join(worktrees, 'acme', 'app', 'gamma');
  git.failures.set(['worktree', 'add', '--no-track', '-b', 'carrier/gamma', path, 'refs/heads/main'].join(' '), { ok: false, code: 128, stderr: 'fatal: https://user:ghp_secret@github.com/acme/app.git' });
  const failed = await client.request('open', { agent: 'claude', folder: repo, worktree: { from: 'main', name: 'gamma' } }).catch((error: Error) => error.message);
  expect(failed).toBe('Git could not create the worktree');
  expect(() => statSync(path)).toThrow();
  expect(base.branches).toEqual(['main', 'feat/x']);
  expect(claude.opened).toEqual([]);
  expect(((await client.request('list')) as any).sessions).toEqual([]);
  git.failures.clear();
  expect(await client.request('open', { agent: 'claude', folder: repo, worktree: { from: 'main', name: 'gamma' } })).toBeDefined(); // the name is free again
  client.close();
});

test('a failed add leaves alone the branch or folder that appeared after the name was checked', async () => {
  const { git, client, repo, worktrees, base } = await worktreeHost();
  const path = join(worktrees, 'acme', 'app', 'raced');
  const run = git.run.bind(git);
  // the person's own git makes the branch and the folder just after the name was checked free; the add then fails
  let raced = false;
  git.run = async (folder, args, options) => {
    if (raced === false && args[0] === 'rev-parse' && args.at(-1) === 'refs/heads/carrier/raced') {
      raced = true;
      base.branches.push('carrier/raced');
      mkdirSync(path, { recursive: true });
    }
    if (args[0] === 'worktree' && args[1] === 'add') return { ok: false, code: 128, stderr: 'fatal: already exists' };
    return run(folder, args, options);
  };
  await expect(client.request('open', { agent: 'claude', folder: repo, worktree: { from: 'main', name: 'raced' } })).rejects.toThrow('Git could not create the worktree');
  expect(raced).toBe(true);
  expect(base.branches).toContain('carrier/raced');
  expect(statSync(path).isDirectory()).toBe(true);
  client.close();
});

test('a session that cannot be created after the worktree exists takes the worktree, its branch and the conversation away', async () => {
  const { git, claude, client, repo, worktrees, base } = await worktreeHost();
  const db = new Database(join(root, 'chat', 'chat.db'));
  db.exec("create trigger no_sessions before insert on sessions begin select raise(abort, 'disk full'); end");
  await expect(client.request('open', { agent: 'claude', folder: repo, worktree: { from: 'main', name: 'delta' } })).rejects.toThrow('internal error');
  expect(() => statSync(join(worktrees, 'acme', 'app', 'delta'))).toThrow();
  expect(base.branches).toEqual(['main', 'feat/x']);
  expect(base.worktrees).toEqual([]);
  expect(claude.conversations.map((c) => c.closed)).toEqual([true]);
  expect(git.calls.map((call) => call.args.slice(0, 2).join(' '))).toEqual(expect.arrayContaining(['worktree add', 'worktree remove', 'branch -D']));

  // an option the provider does not offer refuses the open the same way
  db.exec('drop trigger no_sessions');
  db.close();
  await expect(client.request('open', { agent: 'claude', folder: repo, worktree: { from: 'main', name: 'delta' }, options: { mode: 'plan' } })).rejects.toThrow('no option "mode"');
  expect(() => statSync(join(worktrees, 'acme', 'app', 'delta'))).toThrow();
  expect(base.branches).toEqual(['main', 'feat/x']);
  client.close();
});

/** Opens a session in a worktree, and tells the fake what git would find in that folder. */
async function inWorktree(h: Awaited<ReturnType<typeof worktreeHost>>, name: string, found: { status?: string[]; unpushed?: number } = {}) {
  const { session } = (await h.client.request('open', { agent: 'claude', folder: h.repo, worktree: { from: 'main', name } })) as { session: { id: string; workspace: { path: string; branch: string } } };
  const { path, branch } = session.workspace;
  h.git.repos.set(path, { head: branch, branches: [branch], status: found.status, unpushed: { [branch]: found.unpushed ?? 0 } });
  return { id: session.id, path, branch };
}
const sessionRows = () => {
  const db = new Database(join(root, 'chat', 'chat.db'), { readonly: true });
  const found = db.prepare('select id from sessions').all() as { id: string }[];
  db.close();
  return found.map((row) => row.id);
};

test('deletePreview says null for a session in the base folder and the path, branch, dirty and unpushed for each worktree, for several at once', async () => {
  const h = await worktreeHost();
  const plain = (await h.client.request('open', { agent: 'claude', folder: h.repo })) as { session: { id: string } };
  const created = await inWorktree(h, 'only-created');
  const dirty = await inWorktree(h, 'dirty', { status: [' M a.ts', '?? b.ts'] });
  const ahead = await inWorktree(h, 'ahead', { unpushed: 3 });
  const preview = (...ids: string[]) => h.client.request('deletePreview', { sessionIds: ids });
  expect(await preview(plain.session.id)).toEqual({ sessions: [{ sessionId: plain.session.id, worktree: null }] });
  expect(await preview(created.id)).toEqual({ sessions: [{ sessionId: created.id, worktree: { path: created.path, branch: 'carrier/only-created', dirty: 0, unpushed: 0 } }] });
  expect(await preview(plain.session.id, dirty.id, ahead.id)).toEqual({
    sessions: [
      { sessionId: plain.session.id, worktree: null },
      { sessionId: dirty.id, worktree: { path: dirty.path, branch: 'carrier/dirty', dirty: 2, unpushed: 0 } },
      { sessionId: ahead.id, worktree: { path: ahead.path, branch: 'carrier/ahead', dirty: 0, unpushed: 3 } },
    ],
  });
  // it only reads: the branch is a full ref and the exclusion one value
  expect(h.git.calls.find((call) => call.args[0] === 'rev-list')!.args).toEqual(['rev-list', '--count', 'refs/heads/carrier/only-created', '--not', '--exclude=carrier/only-created', '--branches', '--remotes']);
  expect(h.git.calls.filter((call) => call.args[0] === 'worktree' && call.args[1] === 'remove')).toEqual([]);
  h.client.close();
});

test('deletePreview reads the worktrees one session at a time', async () => {
  const h = await worktreeHost();
  const ids = [(await inWorktree(h, 'one')).id, (await inWorktree(h, 'two')).id, (await inWorktree(h, 'three')).id];
  const run = h.git.run.bind(h.git);
  let running = 0;
  let most = 0;
  h.git.run = async (folder, args, options) => {
    running += 1;
    most = Math.max(most, running);
    await new Promise((done) => setTimeout(done, 5));
    running -= 1;
    return run(folder, args, options);
  };
  await h.client.request('deletePreview', { sessionIds: ids });
  expect(most).toBeLessThanOrEqual(2); // the two reads of one worktree, never those of several
  h.client.close();
});

test('deletePreview refuses the whole request when one id is unknown, and reads nothing', async () => {
  const h = await worktreeHost();
  const one = await inWorktree(h, 'known');
  const before = h.git.calls.length;
  await expect(h.client.request('deletePreview', { sessionIds: [one.id, '3f2b6a52-8f5e-4a63-9d5b-0a1d2c3e4f50'] })).rejects.toThrow('There is no such session');
  expect(h.git.calls).toHaveLength(before);
  h.client.close();
});

test('deletePreview of a worktree whose folder is gone counts 0 instead of failing', async () => {
  const h = await worktreeHost();
  const lost = await inWorktree(h, 'lost');
  rmSync(lost.path, { recursive: true });
  expect(await h.client.request('deletePreview', { sessionIds: [lost.id] })).toEqual({ sessions: [{ sessionId: lost.id, worktree: { path: lost.path, branch: 'carrier/lost', dirty: 0, unpushed: 0 } }] });
  h.client.close();
});

test('delete removes the worktree, then its branch, then the session with its events, and leaves the base folder and other branches alone', async () => {
  const h = await worktreeHost();
  const doomed = await inWorktree(h, 'doomed');
  const kept = await inWorktree(h, 'kept');
  const mark = h.git.calls.length;
  await h.client.request('delete', { sessionId: doomed.id });
  expect(h.git.calls.slice(mark).map((call) => ({ folder: call.folder, args: call.args }))).toEqual([
    { folder: h.repo, args: ['worktree', 'remove', '--force', doomed.path] },
    { folder: h.repo, args: ['rev-parse', '--verify', '--quiet', 'refs/heads/carrier/doomed'] },
    { folder: h.repo, args: ['branch', '-D', 'carrier/doomed'] },
  ]);
  expect(() => statSync(doomed.path)).toThrow();
  expect(h.base.branches).toEqual(['main', 'feat/x', 'carrier/kept']);
  expect(h.base.head).toBe('feat/x');
  expect(h.base.status).toEqual([' M a.ts']);
  expect(statSync(kept.path).isDirectory()).toBe(true);
  expect(sessionRows()).toEqual([kept.id]);
  h.client.close();
});

test('delete of a session in the base folder runs no git and removes only the session', async () => {
  const h = await worktreeHost();
  const plain = (await h.client.request('open', { agent: 'claude', folder: h.repo })) as { session: { id: string } };
  const mark = h.git.calls.length;
  await h.client.request('delete', { sessionId: plain.session.id });
  expect(h.git.calls.slice(mark)).toEqual([]);
  expect(sessionRows()).toEqual([]);
  h.client.close();
});

test('a worktree that cannot be removed stops the deletion with a reason in words, and the session stays; a branch that cannot be deleted does too', async () => {
  const h = await worktreeHost();
  const stuck = await inWorktree(h, 'stuck');
  h.git.failures.set(['worktree', 'remove', '--force', stuck.path].join(' '), { ok: false, code: 128, stderr: 'fatal: https://user:ghp_secret@github.com/acme/app.git' });
  const refusal = await h.client.request('delete', { sessionId: stuck.id }).catch((error: Error) => error.message);
  expect(refusal).toBe('Git could not remove the worktree, so the session was kept');
  expect(h.git.calls.some((call) => call.args[0] === 'branch' && call.args[1] === '-D')).toBe(false); // the order: no branch before the folder
  expect(sessionRows()).toEqual([stuck.id]);
  expect(h.base.branches).toContain('carrier/stuck');
  expect(statSync(stuck.path).isDirectory()).toBe(true);

  h.git.failures.clear();
  h.git.failures.set('branch -D carrier/stuck', { ok: false, code: 1, stderr: 'error' });
  await expect(h.client.request('delete', { sessionId: stuck.id })).rejects.toThrow('Git could not delete the branch of the worktree, so the session was kept');
  expect(sessionRows()).toEqual([stuck.id]);
  h.git.failures.clear();
  await h.client.request('delete', { sessionId: stuck.id }); // the folder is already gone: git only forgets it, and the branch goes
  expect(h.base.branches).not.toContain('carrier/stuck');
  expect(sessionRows()).toEqual([]);
  h.client.close();
});

test('when the base folder is gone the worktree folder is removed directly, the branch is left and the session goes', async () => {
  const h = await worktreeHost();
  const orphan = await inWorktree(h, 'orphan');
  rmSync(h.repo, { recursive: true });
  const mark = h.git.calls.length;
  await h.client.request('delete', { sessionId: orphan.id });
  expect(h.git.calls.slice(mark)).toEqual([]);
  expect(() => statSync(orphan.path)).toThrow();
  expect(h.base.branches).toContain('carrier/orphan');
  expect(sessionRows()).toEqual([]);
  h.client.close();
});

test('a record whose path lies outside the worktrees folder, or whose branch is not a carrier one, is refused and nothing is removed', async () => {
  const h = await worktreeHost();
  const victim = join(root, 'precious');
  mkdirSync(victim);
  writeFileSync(join(victim, 'file'), 'keep');
  const outside = await inWorktree(h, 'outside');
  const sneaky = await inWorktree(h, 'sneaky');
  const raw = new Database(join(root, 'chat', 'chat.db'));
  raw.prepare('update sessions set worktreePath = ? where id = ?').run(victim, outside.id);
  raw.prepare('update sessions set worktreePath = ? where id = ?').run(join(h.worktrees, '..', '..', 'precious'), sneaky.id);
  const dashed = await inWorktree(h, 'dashed');
  raw.prepare('update sessions set worktreeBranch = ? where id = ?').run('main', dashed.id);
  raw.close();
  const mark = h.git.calls.length;
  for (const id of [outside.id, sneaky.id, dashed.id]) await expect(h.client.request('delete', { sessionId: id })).rejects.toThrow('not one Carrier made, so nothing was removed');
  expect(h.git.calls.slice(mark)).toEqual([]);
  expect(readFileSync(join(victim, 'file'), 'utf8')).toBe('keep');
  expect(h.base.branches).toContain('main');
  expect(statSync(dashed.path).isDirectory()).toBe(true);
  expect(sessionRows()).toHaveLength(3);
  // the base folder gone does not turn a tampered record into a direct removal
  rmSync(h.repo, { recursive: true });
  await expect(h.client.request('delete', { sessionId: outside.id })).rejects.toThrow('not one Carrier made');
  expect(readFileSync(join(victim, 'file'), 'utf8')).toBe('keep');
  h.client.close();
});

test('archive and unarchive keep the worktree, its folder and its branch', async () => {
  const h = await worktreeHost();
  const kept = await inWorktree(h, 'archived');
  const mark = h.git.calls.length;
  await h.client.request('archive', { sessionId: kept.id, archived: true });
  await h.client.request('archive', { sessionId: kept.id, archived: false });
  expect(h.git.calls.slice(mark)).toEqual([]);
  expect(statSync(kept.path).isDirectory()).toBe(true);
  expect(h.base.branches).toContain('carrier/archived');
  expect(sessionRows()).toEqual([kept.id]);
  h.client.close();
});
