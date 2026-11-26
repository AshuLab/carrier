import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { connect, type Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { acquireLock } from '../storage/lock.ts';
import type { EpicReply, EventsReply, FileDiffReply, FilesReply } from './replies.ts';
import { RecoverRefused } from '../orchestration/recover-refused.ts';
import { ReloadRefused } from '../orchestration/reload-refused.ts';
import { ResumeRefused } from '../orchestration/resume-refused.ts';
import { editBehavior, setWatchedRepos } from '../config/engine-edit.ts';
import { engineConfigPathOf } from '../config/places.ts';
import { validEngineFile } from '../config/testing.ts';
import { withEngine, writeEngineConfig, type ConfigReply } from './config.ts';
import { request, socketPathFits, startControlServer, type EngineFileRequest } from './server.ts';

let dir: string;
let sockets: Socket[];
let closers: (() => void)[];
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'cs-')) // short: a socket path holds 103 bytes on macOS;
  sockets = [];
  closers = [];
});
afterEach(() => {
  for (const socket of sockets) socket.destroy();
  for (const close of closers) close();
  rmSync(dir, { recursive: true, force: true });
});

const snapshotData = { now: 1, epics: [{ repo: 'AshuLab/a', issue: 5 }] };
const path = () => join(dir, 'control.sock');

// Fake controls: a pause flag the snapshot reads, a counter of checks, and one execution with output.
const executionId = '3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c';
function fakeControls() {
  const state = { paused: false, polls: 0, repoPages: [] as number[] };
  const logs = vi.fn((id: string, count: number) => (id === executionId ? ['one', 'two', 'three'].slice(-count) : []));
  return { state, logs, controls: { poll: () => void state.polls++, setPaused: (paused: boolean) => void (state.paused = paused), logs, sessions: () => ({ sessions: [] }), events: (_id: string, _after: number, _limit: number): EventsReply | null => ({ events: [], next: 0, running: false, structured: true }), epic: (): EpicReply | null | Promise<EpicReply | null> => ({ stages: [], rounds: [], slices: [], slicesTruncated: false, threads: [], threadsTruncated: false, worktrees: [], branch: null, pr: null }), files: (): FilesReply | null | Promise<FilesReply | null> => ({ sections: [], total: null, truncated: false }), fileDiff: (_repo: string, _issue: number, _section: string, _path: string): FileDiffReply | null | Promise<FileDiffReply | null> => ({ rows: [{ sign: '@', text: '@@ -1 +1 @@' }], truncated: false, note: null }), availableRepos: (page: number) => (state.repoPages.push(page), Promise.resolve({ repos: [{ name: 'AshuLab/carrier', private: true, pushedAt: '2026-10-20T10:00:00Z' }], hasMore: page < 3 })), resumeEpic: () => Promise.resolve(), recoverEpic: () => Promise.resolve(), reload: () => {}, setWatchedRepos: (_repos: string[]): ConfigReply => ({ saved: {}, engine: 'applied' }), editBehavior: (_changes: Parameters<typeof editBehavior>[0]): ConfigReply => ({ saved: {}, engine: 'applied' }), editEngineFile: (_command: EngineFileRequest): ConfigReply => ({ saved: {}, engine: 'applied' }) } };
}

const stop = async () => {};

async function open(snapshot: () => unknown = () => snapshotData, controls = fakeControls().controls) {
  const server = await startControlServer({ stateDir: dir, snapshot, startedAt: 1234, controls, stop });
  closers.push(server.close);
  return server;
}

// A plain client: the lines it sends are the ones the app sends, and `next()` resolves with the next line received.
async function client() {
  const socket = connect(path());
  sockets.push(socket);
  socket.setEncoding('utf8');
  const lines: string[] = [];
  const waiting: ((line: string) => void)[] = [];
  let buffer = '';
  let closed = false;
  socket.on('data', (chunk: string) => {
    buffer += chunk;
    for (let end = buffer.indexOf('\n'); end >= 0; end = buffer.indexOf('\n')) {
      const line = buffer.slice(0, end);
      buffer = buffer.slice(end + 1);
      (waiting.shift() ?? ((l) => lines.push(l)))(line);
    }
  });
  socket.on('close', () => (closed = true));
  socket.on('error', () => {});
  const next = () => new Promise<any>((resolve) => (lines.length > 0 ? resolve(JSON.parse(lines.shift()!)) : waiting.push((line) => resolve(JSON.parse(line)))));
  const hello = await next();
  return {
    hello,
    socket,
    next,
    ask: async (line: string) => (socket.write(`${line}\n`), next()),
    isClosed: () => closed,
    closedEvent: () => new Promise<void>((resolve) => (closed ? resolve() : socket.once('close', () => resolve()))),
  };
}

test('a client gets a hello, and the snapshot as JSON when it asks', async () => {
  await open();
  const c = await client();
  expect(c.hello).toEqual({ event: 'hello', protocol: 1, pid: process.pid, startedAt: 1234, version: JSON.parse(readFileSync('package.json', 'utf8')).version, capabilities: ['sessions', 'events', 'epic', 'files', 'fileDiff', 'availableRepos', 'availableReposPaged', 'resumeEpic', 'resumeFromStage', 'resumeReviewerOptions', 'recoverEpic', 'reload', 'config', 'extraReviewers'] });
  expect(await c.ask('{"id":1,"cmd":"snapshot"}')).toEqual({ id: 1, ok: true, data: snapshotData });
  expect(await c.ask('{"id":7,"cmd":"snapshot"}')).toMatchObject({ id: 7, ok: true });
});

test('several requests in one write get one reply each, in order, and a request split across writes is one request', async () => {
  await open();
  const c = await client();
  c.socket.write('{"id":1,"cmd":"snapshot"}\n{"id":2,"cmd":"snap');
  expect((await c.next()).id).toBe(1);
  c.socket.write('shot"}\n');
  expect((await c.next()).id).toBe(2);
});

test('every command in the schema gets a real reply, none is "not supported"', async () => {
  const stopped = vi.fn(async () => {});
  const server = await startControlServer({ stateDir: dir, snapshot: () => snapshotData, startedAt: 1234, controls: fakeControls().controls, stop: stopped });
  closers.push(server.close);
  const c = await client();
  const commands = [
    '{"id":1,"cmd":"snapshot"}',
    '{"id":2,"cmd":"pause"}',
    '{"id":3,"cmd":"resume"}',
    '{"id":4,"cmd":"checkNow"}',
    `{"id":5,"cmd":"tail","executionId":"${executionId}","lines":1}`,
    '{"id":6,"cmd":"sessions","repo":"AshuLab/carrier","issue":5}',
    '{"id":7,"cmd":"epic","repo":"AshuLab/carrier","issue":5}',
    '{"id":8,"cmd":"stop"}',
  ];
  for (const [index, line] of commands.entries()) expect(await c.ask(line)).toMatchObject({ id: index + 1, ok: true });
  await vi.waitFor(() => expect(stopped).toHaveBeenCalledTimes(1));
});

test('pause and resume reply ok and the next snapshot shows it', async () => {
  const fake = fakeControls();
  await open(() => ({ paused: fake.state.paused }), fake.controls);
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"pause"}')).toEqual({ id: 1, ok: true });
  expect((await c.ask('{"id":2,"cmd":"snapshot"}')).data).toEqual({ paused: true });
  expect(await c.ask('{"id":3,"cmd":"resume"}')).toEqual({ id: 3, ok: true });
  expect((await c.ask('{"id":4,"cmd":"snapshot"}')).data).toEqual({ paused: false });
});

test('checkNow replies ok and starts one GitHub check', async () => {
  const fake = fakeControls();
  await open(undefined, fake.controls);
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"checkNow"}')).toEqual({ id: 1, ok: true });
  expect(fake.state.polls).toBe(1);
});

test('tail replies the lines the panel shows, and an empty array for an execution with no output', async () => {
  const fake = fakeControls();
  await open(undefined, fake.controls);
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"tail","executionId":"${executionId}","lines":2}`)).toEqual({ id: 1, ok: true, data: ['two', 'three'] });
  expect(fake.logs).toHaveBeenCalledWith(executionId, 2);
  expect(await c.ask('{"id":2,"cmd":"tail","executionId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","lines":500}')).toEqual({ id: 2, ok: true, data: [] });
});

test.each([
  ['a path', '"../../etc/passwd"', 5],
  ['an empty id', '""', 5],
  ['a UUID with a suffix', `"${executionId}/.."`, 5],
  ['no id', 'null', 5],
  ['zero lines', `"${executionId}"`, 0],
  ['501 lines', `"${executionId}"`, 501],
  ['a fractional count', `"${executionId}"`, 1.5],
  ['a string count', `"${executionId}"`, '"5"'],
  ['no count', `"${executionId}"`, undefined],
])('a tail with %s is a validation error and reads nothing', async (_name, id, lines) => {
  const fake = fakeControls();
  await open(undefined, fake.controls);
  const c = await client();
  const count = lines === undefined ? '' : `,"lines":${lines}`;
  expect(await c.ask(`{"id":3,"cmd":"tail","executionId":${id}${count}}`)).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(fake.logs).not.toHaveBeenCalled();
});

test('an epic request for an unknown epic is an error reply', async () => {
  await open(undefined, { ...fakeControls().controls, epic: () => null });
  expect(await (await client()).ask('{"id":1,"cmd":"epic","repo":"a_b.c-d/e.f","issue":1}')).toEqual({ id: 1, ok: false, error: 'unknown epic', code: 'epic.unknown', params: {} });
});

test('an epic request that throws is an error reply, not a dead server', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  await open(undefined, { ...fakeControls().controls, epic: () => { throw new Error('boom'); } });
  const c = await client();
  expect(await c.ask('{"id":2,"cmd":"epic","repo":"a/b","issue":1}')).toEqual({ id: 2, ok: false, error: 'internal error', code: 'request.internal', params: {} });
  expect(await c.ask('{"id":3,"cmd":"snapshot"}')).toMatchObject({ id: 3, ok: true });
});

test('events answers with the reply, and an unknown execution or a failure are errors', async () => {
  const reply = { events: [], next: 7, running: true, structured: true };
  const events = vi.fn((_id: string, _after: number, _limit: number) => reply);
  await open(undefined, { ...fakeControls().controls, events });
  const c = await client();
  expect(await c.ask(`{"id":9,"cmd":"events","executionId":"${executionId}","limit":200}`)).toEqual({ id: 9, ok: true, data: reply });
  expect(events).toHaveBeenLastCalledWith(executionId, 0, 200);
  await c.ask(`{"id":10,"cmd":"events","executionId":"${executionId}","after":5,"limit":1}`);
  expect(events).toHaveBeenLastCalledWith(executionId, 5, 1);
  await open(undefined, { ...fakeControls().controls, events: () => null });
  expect(await (await client()).ask(`{"id":1,"cmd":"events","executionId":"${executionId}","limit":1}`)).toEqual({ id: 1, ok: false, error: 'unknown execution', code: 'execution.unknown', params: {} });
  await open(undefined, { ...fakeControls().controls, events: () => { throw new Error('boom'); } });
  expect(await (await client()).ask(`{"id":2,"cmd":"events","executionId":"${executionId}","limit":1}`)).toEqual({ id: 2, ok: false, error: 'internal error', code: 'request.internal', params: {} });
});

test('fileDiff answers with the reply; an unknown file or a failure are errors, never git\'s message', async () => {
  const asked: unknown[] = [];
  await open(undefined, { ...fakeControls().controls, fileDiff: (...args) => (asked.push(args), { rows: [], truncated: false, note: 'binary' }) });
  const c = await client();
  expect(await c.ask('{"id":9,"cmd":"fileDiff","repo":"AshuLab/carrier","issue":5,"section":"slice-12","path":"src/a.ts"}')).toEqual({ id: 9, ok: true, data: { rows: [], truncated: false, note: 'binary' } });
  expect(asked).toEqual([['AshuLab/carrier', 5, 'slice-12', 'src/a.ts']]);
  await open(undefined, { ...fakeControls().controls, fileDiff: () => null });
  expect(await (await client()).ask('{"id":1,"cmd":"fileDiff","repo":"a/b","issue":1,"section":"lane-1","path":"a"}')).toEqual({ id: 1, ok: false, error: 'unknown file', code: 'file.unknown', params: {} });
  await open(undefined, { ...fakeControls().controls, fileDiff: () => { throw new Error('fatal: /secret/path is not a git repository'); } });
  expect(await (await client()).ask('{"id":2,"cmd":"fileDiff","repo":"a/b","issue":1,"section":"slice-1","path":"a"}')).toEqual({ id: 2, ok: false, error: 'internal error', code: 'request.internal', params: {} });
});

test('files answers with the reply, and an unknown epic or a failure are errors', async () => {
  await open();
  const c = await client();
  const empty = { sections: [], total: null, truncated: false };
  expect(await c.ask('{"id":9,"cmd":"files","repo":"AshuLab/carrier","issue":5}')).toEqual({ id: 9, ok: true, data: empty });
  expect(await c.ask(`{"id":10,"cmd":"files","repo":"AshuLab/carrier","issue":5,"executionId":"${executionId}"}`)).toEqual({ id: 10, ok: true, data: empty });
  await open(undefined, { ...fakeControls().controls, files: () => null });
  expect(await (await client()).ask('{"id":1,"cmd":"files","repo":"a/b","issue":1}')).toEqual({ id: 1, ok: false, error: 'unknown epic', code: 'epic.unknown', params: {} });
  await open(undefined, { ...fakeControls().controls, files: () => { throw new Error('boom'); } });
  expect(await (await client()).ask('{"id":2,"cmd":"files","repo":"a/b","issue":1}')).toEqual({ id: 2, ok: false, error: 'internal error', code: 'request.internal', params: {} });
});

test('epic, files and fileDiff may answer with a promise: a value, null and a rejection reply as they do synchronously', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  const empty = { sections: [], total: null, truncated: false };
  const diff = { rows: [], truncated: false, note: 'binary' as const };
  const ask = { epic: '{"id":1,"cmd":"epic","repo":"a/b","issue":1}', files: '{"id":2,"cmd":"files","repo":"a/b","issue":1}', fileDiff: '{"id":3,"cmd":"fileDiff","repo":"a/b","issue":1,"section":"lane-1","path":"a"}' };
  await open(undefined, { ...fakeControls().controls, files: () => Promise.resolve(empty), fileDiff: () => Promise.resolve(diff), epic: () => Promise.resolve(null) });
  const c = await client();
  expect(await c.ask(ask.files)).toEqual({ id: 2, ok: true, data: empty });
  expect(await c.ask(ask.fileDiff)).toEqual({ id: 3, ok: true, data: diff });
  expect(await c.ask(ask.epic)).toEqual({ id: 1, ok: false, error: 'unknown epic', code: 'epic.unknown', params: {} });
  await open(undefined, { ...fakeControls().controls, files: () => Promise.resolve(null), fileDiff: () => Promise.resolve(null) });
  const other = await client();
  expect(await other.ask(ask.files)).toEqual({ id: 2, ok: false, error: 'unknown epic', code: 'epic.unknown', params: {} });
  expect(await other.ask(ask.fileDiff)).toEqual({ id: 3, ok: false, error: 'unknown file', code: 'file.unknown', params: {} });
  const boom = () => Promise.reject(new Error('fatal: /secret/path is not a git repository'));
  await open(undefined, { ...fakeControls().controls, epic: boom, files: boom, fileDiff: boom });
  const failing = await client();
  for (const line of Object.values(ask)) expect(await failing.ask(line)).toMatchObject({ ok: false, error: 'internal error', code: 'request.internal', params: {} });
  expect(await failing.ask('{"id":4,"cmd":"snapshot"}')).toMatchObject({ id: 4, ok: true });
});

test('a files request that waits does not hold back another connection, and its own connection keeps the order', async () => {
  let release = (_: FilesReply) => {};
  const slow = new Promise<FilesReply>((resolve) => (release = resolve));
  await open(undefined, { ...fakeControls().controls, files: () => slow });
  const first = await client();
  const second = await client();
  const waiting = first.ask('{"id":1,"cmd":"files","repo":"a/b","issue":1}');
  const behind = first.ask('{"id":2,"cmd":"snapshot"}');
  expect(await second.ask('{"id":3,"cmd":"snapshot"}')).toMatchObject({ id: 3, ok: true });
  release({ sections: [], total: null, truncated: false });
  expect(await waiting).toMatchObject({ id: 1, ok: true });
  expect(await behind).toMatchObject({ id: 2, ok: true });
});

test('availableRepos answers the page asked for with hasMore, and page 1 without one', async () => {
  const { state, controls } = fakeControls();
  await open(undefined, controls);
  const c = await client();
  const repos = [{ name: 'AshuLab/carrier', private: true, pushedAt: '2026-10-20T10:00:00Z' }];
  expect(await c.ask('{"id":4,"cmd":"availableRepos"}')).toEqual({ id: 4, ok: true, data: { repos, hasMore: true } });
  expect(await c.ask('{"id":5,"cmd":"availableRepos","page":3}')).toEqual({ id: 5, ok: true, data: { repos, hasMore: false } });
  expect(state.repoPages).toEqual([1, 3]);
});

test('availableRepos with a page outside 1 to 100, not an integer, or an extra field is a validation error', async () => {
  const { state, controls } = fakeControls();
  await open(undefined, controls);
  const c = await client();
  for (const [id, extra] of [[1, '"page":0'], [2, '"page":101'], [3, '"page":1.5'], [4, '"page":"2"'], [5, '"affiliation":"all"']] as const) {
    expect(await c.ask(`{"id":${id},"cmd":"availableRepos",${extra}}`)).toEqual({ id, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  }
  expect(await c.ask('{"id":6,"cmd":"availableRepos","page":100}')).toMatchObject({ id: 6, ok: true });
  expect(state.repoPages).toEqual([100]);
});

test('availableRepos that fails is a "github unavailable" reply without the reason, and the server goes on', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  await open(undefined, { ...fakeControls().controls, availableRepos: () => Promise.reject(new Error('gh: HTTP 401 token ghp_secret')) });
  const c = await client();
  const reply = await c.ask('{"id":2,"cmd":"availableRepos"}');
  expect(reply).toEqual({ id: 2, ok: false, error: 'github unavailable', code: 'github.unavailable', params: {} });
  expect(JSON.stringify(reply)).not.toContain('ghp_secret');
  expect(await c.ask('{"id":3,"cmd":"snapshot"}')).toMatchObject({ id: 3, ok: true });
});

test('a slow availableRepos does not hold other connections, and replies on its own connection keep their order', async () => {
  let finish: (page: { repos: []; hasMore: boolean }) => void = () => {};
  await open(undefined, { ...fakeControls().controls, availableRepos: () => new Promise((resolve) => (finish = resolve)) });
  const slow = await client();
  const other = await client();
  const first = slow.ask('{"id":1,"cmd":"availableRepos"}');
  const second = slow.ask('{"id":2,"cmd":"snapshot"}');
  expect(await other.ask('{"id":9,"cmd":"snapshot"}')).toMatchObject({ id: 9, ok: true });
  finish({ repos: [], hasMore: false });
  expect(await first).toMatchObject({ id: 1, ok: true });
  expect(await second).toMatchObject({ id: 2, ok: true });
});

test('resumeEpic answers ok once the engine says the epic started, and asks it for that repo and issue', async () => {
  const resumeEpic = vi.fn(() => Promise.resolve());
  await open(undefined, { ...fakeControls().controls, resumeEpic });
  expect(await (await client()).ask('{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5}')).toEqual({ id: 4, ok: true });
  expect(resumeEpic).toHaveBeenCalledWith('AshuLab/carrier', 5, { author: undefined, reviewer: undefined });
});

test('resumeEpic passes the options named for each role, a role left out as undefined', async () => {
  const resumeEpic = vi.fn(() => Promise.resolve());
  await open(undefined, { ...fakeControls().controls, resumeEpic });
  const c = await client();
  expect(await c.ask('{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"author":"codex"}')).toEqual({ id: 4, ok: true });
  expect(resumeEpic).toHaveBeenLastCalledWith('AshuLab/carrier', 5, { author: 'codex', reviewer: undefined });
  expect(await c.ask('{"id":5,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"reviewer":"claude"}')).toEqual({ id: 5, ok: true });
  expect(resumeEpic).toHaveBeenLastCalledWith('AshuLab/carrier', 5, { author: undefined, reviewer: 'claude' });
});

test('resumeEpic passes the option of each extra reviewer by its key, and refuses the old names and a key that is not a slug', async () => {
  const resumeEpic = vi.fn(() => Promise.resolve());
  await open(undefined, { ...fakeControls().controls, resumeEpic });
  const c = await client();
  expect(await c.ask('{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"extraReviewers":{"seguridad-api":"codex","usabilidad":"claude"}}')).toEqual({ id: 4, ok: true });
  expect(resumeEpic).toHaveBeenLastCalledWith('AshuLab/carrier', 5, { author: undefined, reviewer: undefined, extraReviewers: { 'seguridad-api': 'codex', usabilidad: 'claude' } });
  for (const extra of ['"reviewer2":"codex"', '"reviewer3":"codex"', '"reviewer4":"codex"', '"extraReviewers":{"2":"codex"}', '"extraReviewers":{"Seguridad":"codex"}', '"extraReviewers":["codex"]', '"extraReviewers":{"a":"codex","b":"codex","c":"codex","d":"codex"}']) {
    expect(await c.ask(`{"id":5,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,${extra}}`)).toMatchObject({ id: 5, ok: false });
  }
  expect(resumeEpic).toHaveBeenCalledTimes(1);
});

test('resumeEpic passes the stage named in from, and refuses any other', async () => {
  const resumeEpic = vi.fn(() => Promise.resolve());
  await open(undefined, { ...fakeControls().controls, resumeEpic });
  const c = await client();
  for (const from of ['ship', 'review', 'fix']) {
    expect(await c.ask(`{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"from":"${from}"}`)).toEqual({ id: 4, ok: true });
    expect(resumeEpic).toHaveBeenLastCalledWith('AshuLab/carrier', 5, { author: undefined, reviewer: undefined, from });
  }
  resumeEpic.mockClear();
  for (const from of ['"merged"', '""', '"Review"', '1', 'null']) expect(await c.ask(`{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"from":${from}}`)).toMatchObject({ ok: false });
  expect(resumeEpic).not.toHaveBeenCalled();
});

test('resumeEpic passes extraRounds, a positive whole number, and refuses zero, a negative, a fraction and anything else', async () => {
  const resumeEpic = vi.fn(() => Promise.resolve());
  await open(undefined, { ...fakeControls().controls, resumeEpic });
  const c = await client();
  expect(await c.ask('{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"from":"review","extraRounds":3}')).toEqual({ id: 4, ok: true });
  expect(resumeEpic).toHaveBeenLastCalledWith('AshuLab/carrier', 5, { author: undefined, reviewer: undefined, from: 'review', extraRounds: 3 });
  resumeEpic.mockClear();
  for (const extraRounds of ['0', '-1', '1.5', '"3"', 'null', '1e400']) expect(await c.ask(`{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"from":"review","extraRounds":${extraRounds}}`)).toEqual({ id: 4, ok: false, error: 'invalid request: extraRounds takes a positive whole number', code: 'request.extraRounds', params: {} });
  expect(await c.ask('{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"from":"merged"}')).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(resumeEpic).not.toHaveBeenCalled();
});

test('resumeEpic passes --from review and --from fix alike, and the engine\'s refusal of a moved head at fix is that reason in the reply', async () => {
  const resumeEpic = vi.fn(() => Promise.resolve());
  resumeEpic.mockResolvedValueOnce().mockRejectedValueOnce(new ResumeRefused('resume.pullRequestHeadChanged', 'pull request head changed'));
  await open(undefined, { ...fakeControls().controls, resumeEpic });
  const c = await client();
  expect(await c.ask('{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"from":"review"}')).toEqual({ id: 4, ok: true });
  expect(await c.ask('{"id":5,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5,"from":"fix"}')).toEqual({ id: 5, ok: false, error: 'pull request head changed', code: 'resume.pullRequestHeadChanged', params: {} });
  expect(resumeEpic).toHaveBeenNthCalledWith(1, 'AshuLab/carrier', 5, { author: undefined, reviewer: undefined, from: 'review', extraRounds: undefined });
  expect(resumeEpic).toHaveBeenNthCalledWith(2, 'AshuLab/carrier', 5, { author: undefined, reviewer: undefined, from: 'fix', extraRounds: undefined });
});

// the refusal table: each reason of the engine reaches the client as it is, with its code
test.each([
  ['epic.unknown', 'unknown epic'],
  ['resume.notStopped', 'not stopped'],
  ['github.unavailable', 'github unavailable'],
  ['resume.didNotRestart', 'did not restart'],
  ['resume.optionUnknown', 'unknown option'],
  ['resume.roleUnknown', 'no such role'],
  ['resume.reviewersWithoutKey', 'reviewers without a key'],
  ['resume.noPullRequest', 'no pull request'],
  ['resume.pullRequestNotOpen', 'pull request not open'],
  ['resume.pullRequestHeadChanged', 'pull request head changed'],
  ['resume.extraRoundsNeedStage', 'extra rounds need a stage'],
  ['resume.extraRoundsNeedReviewLimit', 'extra rounds need a review limit'],
] as const)('resumeEpic refused with %s answers "%s" as the words', async (code, reason) => {
  await open(undefined, { ...fakeControls().controls, resumeEpic: () => Promise.reject(new ResumeRefused(code, reason)) });
  expect(await (await client()).ask('{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5}')).toEqual({ id: 4, ok: false, error: reason, code, params: {} });
});

test('resumeEpic refused for an extra reviewer the epic does not have carries its key as the parameter', async () => {
  await open(undefined, { ...fakeControls().controls, resumeEpic: () => Promise.reject(new ResumeRefused('resume.extraReviewerUnknown', 'no such extra reviewer', { key: 'rendimiento' })) });
  expect(await (await client()).ask('{"id":4,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5}')).toEqual({ id: 4, ok: false, error: 'no such extra reviewer', code: 'resume.extraReviewerUnknown', params: { key: 'rendimiento' } });
});

test('resumeEpic that fails for any other reason is an "internal error" without the reason, and the server goes on', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  await open(undefined, { ...fakeControls().controls, resumeEpic: () => Promise.reject(new Error('gh: token ghp_secret')) });
  const c = await client();
  const reply = await c.ask('{"id":2,"cmd":"resumeEpic","repo":"AshuLab/carrier","issue":5}');
  expect(reply).toEqual({ id: 2, ok: false, error: 'internal error', code: 'request.internal', params: {} });
  expect(JSON.stringify(reply)).not.toContain('ghp_secret');
  expect(await c.ask('{"id":3,"cmd":"snapshot"}')).toMatchObject({ id: 3, ok: true });
});

test('recoverEpic answers ok once the engine says the epic was continued, and asks it for that repo and issue alone', async () => {
  const recoverEpic = vi.fn(() => Promise.resolve());
  await open(undefined, { ...fakeControls().controls, recoverEpic });
  expect(await (await client()).ask('{"id":4,"cmd":"recoverEpic","repo":"AshuLab/carrier","issue":5}')).toEqual({ id: 4, ok: true });
  expect(recoverEpic.mock.calls).toEqual([['AshuLab/carrier', 5]]);
});

// the refusal table: each reason the engine gives reaches the client as it is, with its code
test.each([
  ['epic.unknown', 'unknown epic'],
  ['recover.notRunning', 'not running'],
  ['recover.agentAlive', 'agent alive'],
  ['recover.notStarted', 'not started'],
  ['recover.nothingToRecover', 'nothing to recover'],
  ['recover.engineUnavailable', 'engine unavailable'],
  ['github.unavailable', 'github unavailable'],
] as const)('recoverEpic refused with %s answers "%s" as the words', async (code, reason) => {
  await open(undefined, { ...fakeControls().controls, recoverEpic: () => Promise.reject(new RecoverRefused(code, reason)) });
  expect(await (await client()).ask('{"id":4,"cmd":"recoverEpic","repo":"AshuLab/carrier","issue":5}')).toEqual({ id: 4, ok: false, error: reason, code, params: {} });
});

test('recoverEpic that fails for any other reason is an "internal error" without the reason, and the server goes on', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  await open(undefined, { ...fakeControls().controls, recoverEpic: () => Promise.reject(new Error('gh: token ghp_secret')) });
  const c = await client();
  const reply = await c.ask('{"id":2,"cmd":"recoverEpic","repo":"AshuLab/carrier","issue":5}');
  expect(reply).toEqual({ id: 2, ok: false, error: 'internal error', code: 'request.internal', params: {} });
  expect(JSON.stringify(reply)).not.toContain('ghp_secret');
  expect(await c.ask('{"id":3,"cmd":"snapshot"}')).toMatchObject({ id: 3, ok: true });
});

test('reload asks the engine to reload and answers ok', async () => {
  const reload = vi.fn();
  await open(undefined, { ...fakeControls().controls, reload });
  expect(await (await client()).ask('{"id":4,"cmd":"reload"}')).toEqual({ id: 4, ok: true });
  expect(reload).toHaveBeenCalledTimes(1);
});

test('reload refused is the problem in the reply, as the lines a start would print, with its code and parameters', async () => {
  const problem = 'Invalid config /c/engine.json:\n  limits.maxReviews: Too small';
  await open(undefined, { ...fakeControls().controls, reload: () => { throw new ReloadRefused('config.invalid', problem); } });
  expect(await (await client()).ask('{"id":4,"cmd":"reload"}')).toEqual({ id: 4, ok: false, error: problem, code: 'config.invalid', params: {} });
});

test('reload refused for a config problem with a known kind answers the key path and the kind as parameters', async () => {
  const problem = 'Invalid config /c/engine.json:\n  repos.2.name: must be owner/name';
  await open(undefined, { ...fakeControls().controls, reload: () => { throw new ReloadRefused('config.problem', problem, { path: 'repos[2]', problem: 'notARepo' }); } });
  expect(await (await client()).ask('{"id":4,"cmd":"reload"}')).toEqual({ id: 4, ok: false, error: problem, code: 'config.problem', params: { path: 'repos[2]', problem: 'notARepo' } });
});

test('reload that fails for any other reason is an "internal error" without the reason, and the server goes on', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  await open(undefined, { ...fakeControls().controls, reload: () => { throw new Error('token ghp_secret'); } });
  const c = await client();
  const reply = await c.ask('{"id":2,"cmd":"reload"}');
  expect(reply).toEqual({ id: 2, ok: false, error: 'internal error', code: 'request.internal', params: {} });
  expect(JSON.stringify(reply)).not.toContain('ghp_secret');
  expect(await c.ask('{"id":3,"cmd":"snapshot"}')).toMatchObject({ id: 3, ok: true });
});

test('reload with any field is refused as an invalid request, without reaching the engine', async () => {
  const reload = vi.fn();
  await open(undefined, { ...fakeControls().controls, reload });
  expect(await (await client()).ask('{"id":4,"cmd":"reload","file":"x"}')).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(reload).not.toHaveBeenCalled();
});

test('the hello no longer lists agentOptions and chooseOptions is refused as an invalid request, without reaching the engine', async () => {
  await open();
  const c = await client();
  expect(c.hello.capabilities).not.toContain('agentOptions');
  expect(await c.ask('{"id":4,"cmd":"chooseOptions","repo":"AshuLab/carrier","issue":5,"author":"codex"}')).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

const validFields = {
  sessions: { repo: 'AshuLab/carrier', issue: 5 },
  events: { executionId, limit: 10 },
  epic: { repo: 'AshuLab/carrier', issue: 5 },
  files: { repo: 'AshuLab/carrier', issue: 5 },
  fileDiff: { repo: 'AshuLab/carrier', issue: 5, section: 'slice-12', path: 'src/a.ts' },
  resumeEpic: { repo: 'AshuLab/carrier', issue: 5, author: 'codex', reviewer: 'claude-ashu', from: 'review', extraRounds: 3 },
  recoverEpic: { repo: 'AshuLab/carrier', issue: 5 },
} as const;
const badRepos = ['', 'carrier', 'a/b/c', '../b', 'a/..', './b', 'a/.', '/b', 'a/', 'a b/c', 'a/b?x', `${'a'.repeat(200)}/b`, 7, null];
const invalid = (cmd: keyof typeof validFields, change: Record<string, unknown>) => ({ id: 3, cmd, ...validFields[cmd], ...change });

const invalidRequests: (readonly [string, Record<string, unknown>])[] = [
  ...(['sessions', 'epic', 'files', 'fileDiff', 'resumeEpic', 'recoverEpic'] as const).flatMap((cmd) => [
    ...badRepos.map((repo) => [`${cmd} with repo ${JSON.stringify(repo)}`, invalid(cmd, { repo })] as const),
    [`${cmd} with issue 0`, invalid(cmd, { issue: 0 })] as const,
    [`${cmd} with a string issue`, invalid(cmd, { issue: '5' })] as const,
    [`${cmd} with a fractional issue`, invalid(cmd, { issue: 1.5 })] as const,
    [`${cmd} with no issue`, invalid(cmd, { issue: undefined })] as const,
    [`${cmd} with no repo`, invalid(cmd, { repo: undefined })] as const,
  ]),
  ...(['events', 'files'] as const).map((cmd) => [`${cmd} with a non-UUID execution id`, invalid(cmd, { executionId: 'not-a-uuid' })] as const),
  ...(['section', 'path'] as const).flatMap((field) => [
    [`fileDiff with an empty ${field}`, invalid('fileDiff', { [field]: '' })] as const,
    [`fileDiff with a numeric ${field}`, invalid('fileDiff', { [field]: 5 })] as const,
    [`fileDiff with no ${field}`, invalid('fileDiff', { [field]: undefined })] as const,
  ]),
  ['fileDiff with an oversize section', invalid('fileDiff', { section: 's'.repeat(101) })],
  ['fileDiff with an oversize path', invalid('fileDiff', { path: 'p'.repeat(501) })],
  ...(['resumeEpic'] as const).flatMap((cmd) =>
    (['author', 'reviewer'] as const).flatMap((role) =>
      ['', 'Codex', 'a b', '1abc', '-a', 'a'.repeat(41), '../x', 7, null].map((option) => [`${cmd} with ${role} ${JSON.stringify(option)}`, invalid(cmd, { [role]: option })] as const),
    ),
  ),
  ...['', 'merged', 'Review', 'ship ', 7, null].map((from) => [`resumeEpic with from ${JSON.stringify(from)}`, invalid('resumeEpic', { from })] as const),
  ['events with no execution id', invalid('events', { executionId: undefined })],
  ['events with no limit', invalid('events', { limit: undefined })],
  ['events with limit 0', invalid('events', { limit: 0 })],
  ['events with an oversize limit', invalid('events', { limit: 201 })],
  ['events with a string limit', invalid('events', { limit: '10' })],
  ['events with a negative cursor', invalid('events', { after: -1 })],
  ['events with a fractional cursor', invalid('events', { after: 0.5 })],
  ['events with a string cursor', invalid('events', { after: '1' })],
  ...(['sessions', 'events', 'epic', 'files', 'fileDiff', 'resumeEpic', 'recoverEpic'] as const).flatMap((cmd) => [
    [`${cmd} with an extra field`, invalid(cmd, { extra: 1 })] as const,
    [`${cmd} with no fields`, { id: 3, cmd }] as const,
  ]),
];
// ADR 0044: the caller never picks an epic's status, stage or round. The fields every request accepts, listed, so a new one is a decision of this test.
// `resumeEpic`'s `from` is the one place a caller names a stage, and only to resume at `review` or `fix` what the epic already has: its round and the rest are the epic's own.
test('no request takes a status, a stage or a round, and each accepts exactly these fields', () => {
  const accepted = Object.fromEntries(request.options.map((option) => [String((option.shape.cmd as any).options?.join('|') ?? (option.shape.cmd as any).value), Object.keys(option.shape).filter((field) => field !== 'cmd' && field !== 'id').sort()]));
  expect(accepted).toEqual({
    'snapshot|pause|resume|checkNow|stop': [],
    tail: ['executionId', 'lines'],
    sessions: ['issue', 'repo'],
    events: ['after', 'executionId', 'limit'],
    epic: ['issue', 'repo'],
    files: ['executionId', 'issue', 'repo'],
    fileDiff: ['issue', 'path', 'repo', 'section'],
    availableRepos: ['page'],
    reload: [],
    resumeEpic: ['author', 'extraReviewers', 'extraRounds', 'from', 'issue', 'lead', 'repo', 'reviewer'],
    recoverEpic: ['issue', 'repo'],
    setWatchedRepos: ['repos'],
    editBehavior: ['changes'],
    editRole: ['changes', 'role'],
    editRepoRole: ['fields', 'repo', 'role'],
    editPersona: ['name', 'prompt', 'role'],
    editFailover: ['first', 'role', 'second'],
    setLeadReviewer: ['draft'],
    setOrchestratorProfile: ['name'],
    addExtraReviewer: ['draft'],
  });
  expect(Object.values(accepted).flat().filter((field) => ['status', 'stage', 'round', 'rounds'].includes(field))).toEqual([]);
});

// a refused extraRounds names its field
test.each([0, -1, 1.5, '3', null])('resumeEpic with extraRounds %j is refused naming extraRounds', async (extraRounds) => {
  await open();
  const c = await client();
  expect(await c.ask(JSON.stringify(invalid('resumeEpic', { extraRounds })))).toEqual({ id: 3, ok: false, error: 'invalid request: extraRounds takes a positive whole number', code: 'request.extraRounds', params: {} });
});

test.each(invalidRequests)('%s is a validation error', async (_name, request) => {
  await open();
  const c = await client();
  expect(await c.ask(JSON.stringify(request))).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('a control that throws is an error reply, not a dead server', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  const fake = fakeControls();
  fake.logs.mockImplementationOnce(() => {
    throw new Error('disk is gone');
  });
  await open(undefined, fake.controls);
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"tail","executionId":"${executionId}","lines":5}`)).toEqual({ id: 1, ok: false, error: 'internal error', code: 'request.internal', params: {} });
  expect(await c.ask('{"id":2,"cmd":"snapshot"}')).toMatchObject({ id: 2, ok: true });
});

test.each([
  ['not JSON', 'hello', null],
  ['an empty line', '', null],
  ['{}', '{}', null],
  ['null', 'null', null],
  ['an array', '[{"id":1,"cmd":"snapshot"}]', null],
  ['a number', '5', null],
  ['a missing id', '{"cmd":"snapshot"}', null],
  ['a zero id', '{"id":0,"cmd":"snapshot"}', null],
  ['a negative id', '{"id":-1,"cmd":"snapshot"}', null],
  ['a fractional id', '{"id":1.5,"cmd":"snapshot"}', null],
  ['a string id', '{"id":"1","cmd":"snapshot"}', null],
  ['a huge id', '{"id":1e400,"cmd":"snapshot"}', null],
  ['an unsafe integer id', '{"id":99999999999999999999,"cmd":"snapshot"}', null],
  ['a null id', '{"id":null,"cmd":"snapshot"}', null],
  ['a missing command', '{"id":3}', 3],
  ['an unknown command', '{"id":3,"cmd":"reboot"}', 3],
  ['an inherited name', '{"id":3,"cmd":"toString"}', 3],
  ['another inherited name', '{"id":3,"cmd":"constructor"}', 3],
  ['a command that is not a string', '{"id":3,"cmd":["snapshot"]}', 3],
  ['an extra field', '{"id":3,"cmd":"snapshot","extra":1}', 3],
  ['a __proto__ key', '{"id":3,"cmd":"snapshot","__proto__":{"cmd":"stop"}}', 3],
  ['a tail without its fields', '{"id":3,"cmd":"tail"}', 3],
  ['a tail with an id that is not a UUID', '{"id":3,"cmd":"tail","executionId":"../../etc/passwd","lines":5}', 3],
  ['a tail with too many lines', '{"id":3,"cmd":"tail","executionId":"3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c","lines":501}', 3],
  ['a snapshot with tail fields', '{"id":3,"cmd":"snapshot","executionId":"3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c","lines":5}', 3],
])('%s gets an error reply, the connection stays open and the snapshot is never taken', async (_name, line, id) => {
  const snapshot = vi.fn(() => snapshotData);
  await open(snapshot);
  const c = await client();
  const reply = await c.ask(line);
  expect(reply).toMatchObject({ id, ok: false });
  expect(typeof reply.error).toBe('string');
  expect(snapshot).not.toHaveBeenCalled();
  // still usable
  expect(await c.ask('{"id":9,"cmd":"snapshot"}')).toMatchObject({ id: 9, ok: true });
});

test('a line over 16 KiB gets the error reply and the connection is closed', async () => {
  const snapshot = vi.fn(() => snapshotData);
  await open(snapshot);
  const c = await client();
  c.socket.write(`{"id":1,"cmd":"snapshot","pad":"${'x'.repeat(16 * 1024)}"}\n`);
  expect(await c.next()).toEqual({ id: null, ok: false, error: 'line too long', code: 'request.tooLong', params: {} });
  await c.closedEvent();
  expect(snapshot).not.toHaveBeenCalled();
});

test('a client that never sends a newline cannot grow the buffer past 16 KiB either', async () => {
  await open();
  const c = await client();
  c.socket.write('x'.repeat(16 * 1024 + 1));
  expect(await c.next()).toMatchObject({ ok: false, error: 'line too long', code: 'request.tooLong', params: {} });
  await c.closedEvent();
});

test('a failing snapshot is an error reply, not a dead server', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  let fail = true;
  await open(() => {
    if (fail) throw new Error('db is gone');
    return snapshotData;
  });
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"snapshot"}')).toEqual({ id: 1, ok: false, error: 'internal error', code: 'request.internal', params: {} });
  fail = false;
  expect(await c.ask('{"id":2,"cmd":"snapshot"}')).toMatchObject({ id: 2, ok: true });
});

test('the socket is 0600 and the state folder is 0700, also when the folder existed with a looser mode', async () => {
  const folder = join(dir, 'state');
  mkdirSync(folder);
  chmodSync(folder, 0o755);
  const lock = acquireLock(folder);
  expect(lock.ok).toBe(true);
  const server = await startControlServer({ stateDir: folder, snapshot: () => snapshotData, startedAt: 1, controls: fakeControls().controls, stop });
  expect(statSync(folder).mode & 0o777).toBe(0o700);
  expect(statSync(join(folder, 'control.sock')).mode & 0o777).toBe(0o600);
  server.close();
  if (lock.ok) lock.release();
});

test('the umask is back as it was once the socket is open', async () => {
  const before = process.umask();
  await open();
  expect(process.umask()).toBe(before);
});

test('closing removes the socket file at once and drops the connections', async () => {
  const server = await open();
  const c = await client();
  expect(existsSync(path())).toBe(true);
  server.close();
  // synchronous: it is gone before the next line of the caller, which is where the lock is released
  expect(existsSync(path())).toBe(false);
  await c.closedEvent();
});

test('a leftover socket file is replaced by a new one that works', async () => {
  writeFileSync(path(), 'leftover of a crash');
  await open();
  expect((await client()).hello.event).toBe('hello');
});

test('a socket that cannot open is logged and leaves a server that closes without failing', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  const server = await startControlServer({ stateDir: join(dir, 'missing', 'folder'), snapshot: () => snapshotData, startedAt: 1, controls: fakeControls().controls, stop });
  expect(() => server.close()).not.toThrow();
});

// A Carrier folder under `dir` whose socket path is `socketBytes` long, padded with `fill`; the folder exists, so a truncated name would be created in it.
const folderOf = (socketBytes: number, fill: string) => {
  const suffix = '/engine/state/control.sock'.length;
  const pad = Math.ceil((socketBytes - suffix - dir.length - 1) / Buffer.byteLength(fill));
  return join(dir, fill.repeat(pad));
};

test('the path fits up to 103 bytes, counted in bytes and not in characters', () => {
  expect(socketPathFits('a'.repeat(103))).toEqual({ fits: true, bytes: 103 });
  expect(socketPathFits('a'.repeat(104))).toEqual({ fits: false, bytes: 104 });
  expect(socketPathFits('é'.repeat(52))).toEqual({ fits: false, bytes: 104 }); // 52 characters
});

test.each([
  ['a long Carrier folder', 'x', 120],
  ['a Carrier folder of multi-byte characters under 103 characters but over 103 bytes', 'é', 110],
])('%s: no socket file anywhere and a warning with the path and its length', async (_name, fill, bytes) => {
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  const stateDir = join(folderOf(bytes, fill), 'engine', 'state');
  mkdirSync(stateDir, { recursive: true });
  const before = readdirSync(dir, { recursive: true }).sort();
  const full = join(stateDir, 'control.sock');
  expect(Buffer.byteLength(full)).toBeGreaterThan(103);
  if (fill === 'é') expect(full.length).toBeLessThan(103);

  const server = await startControlServer({ stateDir, snapshot: () => snapshotData, startedAt: 1, controls: fakeControls().controls, stop });

  expect(readdirSync(dir, { recursive: true }).sort()).toEqual(before);
  const logged = warn.mock.calls.flat().join(' ');
  expect(logged).toContain(full);
  expect(logged).toContain(`${Buffer.byteLength(full)} bytes`);
  expect(() => server.close()).not.toThrow();
});

// The `config` capability: the requests that change engine.json write the file with the code of `config/engine-edit.ts`, then the engine runs on it.
async function openConfig(reload: () => void) {
  const file = engineConfigPathOf(dir);
  writeFileSync(file, JSON.stringify(validEngineFile, null, 2));
  const controls = { ...fakeControls().controls, setWatchedRepos: (repos: string[]) => withEngine(setWatchedRepos(repos, file, dir), reload), editBehavior: (changes: Parameters<typeof editBehavior>[0]) => withEngine(editBehavior(changes, file, dir), reload), editEngineFile: (command: EngineFileRequest) => withEngine(writeEngineConfig(command, file, dir), reload) };
  await open(undefined, controls);
  return { file, c: await client() };
}

test('the hello lists config', async () => {
  await open();
  expect((await client()).hello.capabilities).toContain('config');
});

test('setWatchedRepos writes the list keeping the other keys, makes the engine run on it and answers saved and the engine', async () => {
  const reload = vi.fn();
  const { file, c } = await openConfig(reload);
  const reply = await c.ask('{"id":5,"cmd":"setWatchedRepos","repos":["acme/web","new/one"]}');
  expect(reply).toEqual({ id: 5, ok: true, data: { saved: { repos: [validEngineFile.repos[1], { name: 'new/one' }] }, engine: 'applied' } });
  expect(JSON.parse(readFileSync(file, 'utf8'))).toEqual({ ...validEngineFile, repos: [validEngineFile.repos[1], { name: 'new/one' }] });
  expect(reload).toHaveBeenCalledTimes(1);
});

test('editBehavior writes the values, a default one taken out, and the engine runs on them', async () => {
  const reload = vi.fn();
  const { file, c } = await openConfig(reload);
  const reply = await c.ask('{"id":6,"cmd":"editBehavior","changes":{"pollIntervalMinutes":2,"logLevel":"info","limits":{"maxReviews":5,"maxExecutionHours":"unlimited"}}}');
  expect(reply).toEqual({ id: 6, ok: true, data: { saved: { pollIntervalMinutes: 2, limits: { maxExecutionHours: 'unlimited' } }, engine: 'applied' } });
  expect(JSON.parse(readFileSync(file, 'utf8'))).toEqual({ ...validEngineFile, pollIntervalMinutes: 2, limits: { maxLeadRounds: 2, maxExecutionHours: 'unlimited' } });
  expect(reload).toHaveBeenCalledTimes(1);
});

test('a reload the engine refuses leaves the file saved and says engine refused with the reason as a text code', async () => {
  const problem = 'Invalid config /c/engine.json:\n  repos.2.name: must be owner/name';
  const { file, c } = await openConfig(() => { throw new ReloadRefused('config.problem', problem, { path: 'repos[2]', problem: 'notARepo' }); });
  const reply = await c.ask('{"id":5,"cmd":"setWatchedRepos","repos":["a/b"]}');
  expect(reply).toEqual({ id: 5, ok: true, data: { saved: { repos: [{ name: 'a/b' }] }, engine: 'refused', reason: { code: 'config.problem', params: { path: 'repos[2]', problem: 'notARepo' }, error: problem } } });
  expect(JSON.parse(readFileSync(file, 'utf8')).repos).toEqual([{ name: 'a/b' }]);
});

test.each([
  ['setWatchedRepos', '"repos":["a/b","nope"]', 'nope must be owner/name', { path: 'repos[1]', problem: 'notARepo' }],
  ['setWatchedRepos', '"repos":["a/b","A/B"]', 'A/B is already watched', { path: 'repos[1]', problem: 'alreadyWatched' }],
  ['editBehavior', '"changes":{"limits":{"maxReviews":0}}', 'Must be 1 or more', { path: 'limits.maxReviews', problem: 'tooSmall' }],
  ['editBehavior', '"changes":{"logLevel":"loud"}', 'Must be one of debug, info, warn, error', { path: 'logLevel', problem: 'notOneOf' }],
])('%s with %s is refused with its words, code and params, no reload, and the file is as it was', async (cmd, fields, words, params) => {
  const reload = vi.fn();
  const { file, c } = await openConfig(reload);
  const before = readFileSync(file, 'utf8');
  expect(await c.ask(`{"id":5,"cmd":"${cmd}",${fields}}`)).toEqual({ id: 5, ok: false, error: words, code: 'config.problem', params });
  expect(readFileSync(file, 'utf8')).toBe(before);
  expect(reload).not.toHaveBeenCalled();
});

test.each([
  '{"id":5,"cmd":"setWatchedRepos"}',
  '{"id":5,"cmd":"setWatchedRepos","repos":"a/b"}',
  '{"id":5,"cmd":"setWatchedRepos","repos":[1]}',
  '{"id":5,"cmd":"setWatchedRepos","repos":[],"extra":1}',
  '{"id":5,"cmd":"editBehavior","changes":{"labels":{}}}',
  '{"id":5,"cmd":"editBehavior","changes":{"limits":{"maxReviews":"5"}}}',
  '{"id":5,"cmd":"editBehavior","changes":{"limits":{"idleMinutes":5}}}',
  '{"id":5,"cmd":"editBehavior"}',
])('%s is a validation error', async (line) => {
  const { c } = await openConfig(() => {});
  expect(await c.ask(line)).toEqual({ id: 5, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

// the role requests of engine.json (the writing module's own tables are in src/config/role-edit.test.ts)
test.each([
  ['editRole', '"role":"author","changes":{"provider":"codex","model":"gpt-5","effort":null}', (file: any) => file.agents.author, { profile: 'author-bot', provider: 'codex', model: 'gpt-5' }],
  ['editRepoRole', '"repo":"acme/web","role":"reviewer","fields":{"model":"qwen","persona":{"name":"Rex"}}', (file: any) => file.repos[1].agents.reviewer, { model: 'qwen', persona: { name: 'Rex' } }],
  ['editPersona', '"role":"reviewer","name":"Ada","prompt":null', (file: any) => file.agents.reviewer.persona, { name: 'Ada' }],
  ['editFailover', '"role":"author","first":{"provider":"codex","model":"g"},"second":null', (file: any) => file.failover.roles.author, [{ provider: 'codex', model: 'g' }]],
  ['setLeadReviewer', '"draft":{"identity":{"kind":"gh"},"provider":"claude","model":"opus"}', (file: any) => file.agents.leadReviewer, { profile: 'reviewer-bot', provider: 'claude', model: 'opus' }],
  ['setOrchestratorProfile', '"name":"author-bot"', (file: any) => file.orchestratorProfile, 'author-bot'],
  ['addExtraReviewer', '"draft":{"name":"Seguridad API","type":"security","identity":{"kind":"gh"},"provider":"claude","model":"opus"}', (file: any) => file.agents.extraReviewers, { 'seguridad-api': { type: 'security', name: 'Seguridad API', profile: 'reviewer-bot', provider: 'claude', model: 'opus' } }],
])('%s writes the file, keeping every key it does not touch, makes the engine run on it and answers saved and the engine', async (cmd, fields, read, expected) => {
  const reload = vi.fn();
  const { file, c } = await openConfig(reload);
  const reply = (await c.ask(`{"id":5,"cmd":"${cmd}",${fields}}`)) as { id: number; ok: boolean; data: { engine: string } };
  expect([reply.id, reply.ok, reply.data.engine]).toEqual([5, true, 'applied']);
  const after = JSON.parse(readFileSync(file, 'utf8'));
  expect(read(after)).toEqual(expected);
  expect(Object.keys(after)).toEqual(Object.keys(validEngineFile));
  expect(reload).toHaveBeenCalledTimes(1);
});

test('setLeadReviewer with draft null on a file with no lead reviewer answers saved and the engine runs on it', async () => {
  const reload = vi.fn();
  const { file, c } = await openConfig(reload);
  const before = readFileSync(file, 'utf8');
  expect(await c.ask('{"id":5,"cmd":"setLeadReviewer","draft":null}')).toEqual({ id: 5, ok: true, data: { saved: {}, engine: 'applied' } });
  expect(readFileSync(file, 'utf8')).toBe(before);
  expect(reload).toHaveBeenCalledTimes(1);
});

test.each([
  ['editRole', '"role":"author","changes":{"provider":"nope"}', 'Provider “nope” is not an account of providers.json. Pick another one.', { path: 'agents.author.provider', problem: 'notAnAccount' }],
  ['editRole', '"role":"leadReviewer","changes":{"model":"m"}', 'Lead reviewer has no entry in engine.json. Add it there first.', { path: 'agents.leadReviewer', problem: 'noEntry' }],
  ['editRepoRole', '"repo":"x/y","role":"author","fields":null', 'x/y is no longer in the config file.', { path: 'repos', problem: 'notWatched' }],
  ['editRepoRole', '"repo":"acme/web","role":"author","fields":{"profile":"ghost"}', 'Identity “ghost” is not declared in profiles. Pick another one.', { path: 'repos[1].agents.author.profile', problem: 'notDeclared' }],
  ['editPersona', '"role":"author","name":"","prompt":null', 'The persona’s name cannot be empty. Leave it out instead.', { path: 'agents.author.persona.name', problem: 'empty' }],
  ['editFailover', '"role":"author","first":null,"second":{"provider":"codex"}', 'Then needs a First step.', { path: 'failover.roles.author.1', problem: 'firstMissing' }],
  ['editFailover', '"role":"author","first":{"provider":"claude","model":"m"},"second":null', 'First is the role’s own provider and model, so it would move nowhere.', { path: 'failover.roles.author.0', problem: 'stepOwnRole' }],
  ['setLeadReviewer', '"draft":{"provider":"claude"}', 'The lead reviewer needs an identity, a model.', { path: 'agents.leadReviewer', problem: 'incomplete' }],
  ['addExtraReviewer', '"draft":{"name":"Sec","provider":"claude","model":"opus"}', 'An extra reviewer needs type, identity.', { path: 'agents.extraReviewers.type', problem: 'incomplete' }],
  ['setOrchestratorProfile', '"name":"ghost"', expect.stringContaining('orchestratorProfile'), { path: 'orchestratorProfile', problem: 'invalid' }],
])('%s with %s is refused with its words, code and params, no reload, and the file is as it was', async (cmd, fields, words, params) => {
  const reload = vi.fn();
  const { file, c } = await openConfig(reload);
  const before = readFileSync(file, 'utf8');
  expect(await c.ask(`{"id":5,"cmd":"${cmd}",${fields}}`)).toEqual({ id: 5, ok: false, error: words, code: 'config.problem', params });
  expect(readFileSync(file, 'utf8')).toBe(before);
  expect(reload).not.toHaveBeenCalled();
});

test.each([
  '{"id":5,"cmd":"editRole","role":"author"}',
  '{"id":5,"cmd":"editRole","role":"boss","changes":{}}',
  '{"id":5,"cmd":"editRole","role":"author","changes":{"identity":{"kind":"forge"}}}',
  '{"id":5,"cmd":"editRole","role":"author","changes":{"bots":["a"]}}',
  '{"id":5,"cmd":"editRepoRole","repo":"nope","role":"author","fields":null}',
  '{"id":5,"cmd":"editRepoRole","repo":"a/b","role":"author"}',
  '{"id":5,"cmd":"editRepoRole","repo":"a/b","role":"author","fields":{"accounts":["a"]}}',
  '{"id":5,"cmd":"editPersona","role":"author","name":"a"}',
  '{"id":5,"cmd":"editFailover","role":"author","first":{"model":"m"},"second":null}',
  '{"id":5,"cmd":"editFailover","role":"author","first":null,"second":null,"accounts":["a"]}',
  '{"id":5,"cmd":"setLeadReviewer"}',
  '{"id":5,"cmd":"setOrchestratorProfile","name":5}',
  '{"id":5,"cmd":"addExtraReviewer"}',
  '{"id":5,"cmd":"addExtraReviewer","draft":{"name":"a","key":"a"}}',
])('%s is a validation error', async (line) => {
  const { c } = await openConfig(() => {});
  expect(await c.ask(line)).toEqual({ id: 5, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('a write that fails for any other reason is an internal error without the reason', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  await open(undefined, { ...fakeControls().controls, setWatchedRepos: () => { throw new Error('EACCES /secret/path'); } });
  const reply = await (await client()).ask('{"id":5,"cmd":"setWatchedRepos","repos":[]}');
  expect(reply).toEqual({ id: 5, ok: false, error: 'internal error', code: 'request.internal', params: {} });
});
