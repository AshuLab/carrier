import { mkdtempSync, rmSync, statSync } from 'node:fs';
import { connect, type Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { ChatRefused } from './runner.ts';
import { startChatServer, type ChatControls } from './server.ts';

let dir: string;
let sockets: Socket[];
let closers: (() => void)[];
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'ch-')); // short: a socket path holds 103 bytes on macOS
  sockets = [];
  closers = [];
});
afterEach(() => {
  for (const socket of sockets) socket.destroy();
  for (const close of closers) close();
  rmSync(dir, { recursive: true, force: true });
});

const noClients = { joined: () => {}, left: () => {} };
const controls = (): ChatControls => ({
  agents: () => [],
  list: () => ({ sessions: [] }),
  open: async () => {
    throw new ChatRefused('That folder does not exist');
  },
  resume: async () => ({}),
  send: () => {
    throw new Error('the disk says secret things');
  },
  answer: ({ approvalId, choiceId }) => ({ approvalId, choiceId }),
  interrupt: async () => ({}),
  setOption: async ({ option, value }) => ({ option, value }),
  events: ({ after = 0 }) => ({ after }),
  close: async () => ({}),
  archive: async ({ archived }) => ({ archived }),
  delete: async () => ({}),
  deletePreview: async ({ sessionIds }) => ({ sessionIds }),
  workspace: async ({ folder }) => ({ folder }),
  fetch: async ({ folder }) => ({ folder, fetched: true }),
  suggestName: async ({ folder }) => ({ name: `named-in-${folder}` }),
  checkName: async ({ name }) => ({ valid: true, free: true, name }),
  cloneRepo: async ({ repo }, gone) => {
    seen.push(gone);
    return { repo };
  },
  createProject: async ({ name }) => ({ folder: `/projects/local/${name}` }),
  githubRepos: async ({ page }) => ({ page }),
});
const seen: AbortSignal[] = [];
async function open({ stop = async () => {}, clients = noClients } = {}) {
  const server = await startChatServer({ chatDir: dir, startedAt: 1234, controls: controls(), stop, clients });
  closers.push(server.close);
}

async function client() {
  const socket = connect(join(dir, 'chat.sock'));
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
  return { hello, socket, next, ask: async (line: string) => (socket.write(`${line}\n`), next()), isClosed: () => closed };
}

const uuid = '3f2b6a52-8f5e-4a63-9d5b-0a1d2c3e4f50';

test('the socket is 0600, and a client gets a hello and the empty list', async () => {
  await open();
  expect(statSync(join(dir, 'chat.sock')).mode & 0o777).toBe(0o600);
  const c = await client();
  expect(c.hello).toMatchObject({ event: 'hello', protocol: 1, pid: process.pid, startedAt: 1234, capabilities: ['agents', 'list', 'open', 'resume', 'send', 'answer', 'interrupt', 'setOption', 'events', 'close', 'archive', 'delete', 'workspace', 'fetch', 'suggestName', 'checkName', 'deletePreview', 'cloneRepo', 'createProject', 'githubRepos', 'stop'] });
  expect(typeof c.hello.version).toBe('string');
  expect(await c.ask('{"id":1,"cmd":"list"}')).toEqual({ id: 1, ok: true, data: { sessions: [] } });
});

test.each([
  ['an unknown command', '{"id":2,"cmd":"snapshot"}', 2],
  ['an extra field', '{"id":3,"cmd":"list","pad":true}', 3],
  ['a session id that is not one', '{"id":4,"cmd":"close","sessionId":"../x"}', 4],
  ['a limit over 200', `{"id":5,"cmd":"events","sessionId":"${uuid}","limit":201}`, 5],
  ['an empty message', `{"id":6,"cmd":"send","sessionId":"${uuid}","text":""}`, 6],
  ['an answer with no choice', `{"id":7,"cmd":"answer","sessionId":"${uuid}","approvalId":"a"}`, 7],
  ['a missing id', '{"cmd":"list"}', null],
  ['a bad id', '{"id":-1,"cmd":"list"}', null],
])('%s is "invalid request", with the id only when it is valid', async (_name, line, id) => {
  await open();
  const c = await client();
  expect(await c.ask(line)).toEqual({ id, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":9,"cmd":"list"}')).toMatchObject({ id: 9, ok: true });
});

test('answer is a strict request with a session, an approval and a choice', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"answer","sessionId":"${uuid}","approvalId":"a","choiceId":"deny"}`)).toEqual({ id: 1, ok: true, data: { approvalId: 'a', choiceId: 'deny' } });
});

test('setOption is a strict request with a session, an option and a value', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"setOption","sessionId":"${uuid}","option":"model","value":"haiku"}`)).toEqual({ id: 1, ok: true, data: { option: 'model', value: 'haiku' } });
  expect(await c.ask(`{"id":2,"cmd":"setOption","sessionId":"${uuid}","option":"model"}`)).toEqual({ id: 2, ok: false, error: 'invalid request' });
});

test('archive takes a session and a boolean, delete a session, both strict', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"archive","sessionId":"${uuid}","archived":true}`)).toEqual({ id: 1, ok: true, data: { archived: true } });
  expect(await c.ask(`{"id":2,"cmd":"archive","sessionId":"${uuid}"}`)).toEqual({ id: 2, ok: false, error: 'invalid request' });
  expect(await c.ask(`{"id":3,"cmd":"delete","sessionId":"${uuid}"}`)).toEqual({ id: 3, ok: true, data: {} });
  expect(await c.ask(`{"id":4,"cmd":"delete","sessionId":"${uuid}","archived":true}`)).toEqual({ id: 4, ok: false, error: 'invalid request' });
});

test('deletePreview takes one to 500 session ids and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"deletePreview","sessionIds":["${uuid}"]}`)).toEqual({ id: 1, ok: true, data: { sessionIds: [uuid] } });
  expect(await c.ask(`{"id":2,"cmd":"deletePreview","sessionIds":${JSON.stringify(Array(500).fill(uuid))}}`)).toMatchObject({ id: 2, ok: true });
  expect(await c.ask(`{"id":3,"cmd":"deletePreview","sessionIds":${JSON.stringify(Array(501).fill(uuid))}}`)).toEqual({ id: 3, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":4,"cmd":"deletePreview","sessionIds":[]}')).toEqual({ id: 4, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":5,"cmd":"deletePreview","sessionIds":["../x"]}')).toEqual({ id: 5, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":6,"cmd":"deletePreview"}')).toEqual({ id: 6, ok: false, error: 'invalid request' });
  expect(await c.ask(`{"id":7,"cmd":"deletePreview","sessionIds":["${uuid}"],"force":true}`)).toEqual({ id: 7, ok: false, error: 'invalid request' });
});

test('workspace takes a folder and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"workspace","folder":"/some/where"}')).toEqual({ id: 1, ok: true, data: { folder: '/some/where' } });
  expect(await c.ask('{"id":2,"cmd":"workspace"}')).toEqual({ id: 2, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":3,"cmd":"workspace","folder":""}')).toEqual({ id: 3, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":4,"cmd":"workspace","folder":"/x","fetch":true}')).toEqual({ id: 4, ok: false, error: 'invalid request' });
});

test('fetch takes a folder and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"fetch","folder":"/some/where"}')).toEqual({ id: 1, ok: true, data: { folder: '/some/where', fetched: true } });
  expect(await c.ask('{"id":2,"cmd":"fetch"}')).toEqual({ id: 2, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":3,"cmd":"fetch","folder":""}')).toEqual({ id: 3, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":4,"cmd":"fetch","folder":"/x","prune":false}')).toEqual({ id: 4, ok: false, error: 'invalid request' });
});

test('suggestName takes a folder, checkName a folder and a name, and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"suggestName","folder":"/some/where"}')).toEqual({ id: 1, ok: true, data: { name: 'named-in-/some/where' } });
  expect(await c.ask('{"id":2,"cmd":"suggestName"}')).toEqual({ id: 2, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":3,"cmd":"suggestName","folder":"/x","name":"a"}')).toEqual({ id: 3, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":4,"cmd":"checkName","folder":"/x","name":"a-b"}')).toEqual({ id: 4, ok: true, data: { valid: true, free: true, name: 'a-b' } });
  expect(await c.ask('{"id":5,"cmd":"checkName","folder":"/x"}')).toEqual({ id: 5, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":6,"cmd":"checkName","name":"a"}')).toEqual({ id: 6, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":7,"cmd":"checkName","folder":"","name":"a"}')).toEqual({ id: 7, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":8,"cmd":"checkName","folder":"/x","name":1}')).toEqual({ id: 8, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":9,"cmd":"checkName","folder":"/x","name":"a","force":true}')).toEqual({ id: 9, ok: false, error: 'invalid request' });
});

test('cloneRepo takes one owner/name repo and nothing else, and its signal aborts when the client leaves', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"cloneRepo","repo":"acme/app"}')).toEqual({ id: 1, ok: true, data: { repo: 'acme/app' } });
  for (const [id, extra] of [[2, ''], [3, ',"repo":""'], [4, ',"repo":"../x"'], [5, ',"repo":"a/..'], [6, ',"repo":"a/b/c"'], [7, ',"repo":"solo"'], [8, ',"repo":7'], [9, ',"repo":"a/b","force":true']] as const) {
    expect(await c.ask(`{"id":${id},"cmd":"cloneRepo"${extra}${id === 5 ? '"' : ''}}`)).toEqual({ id, ok: false, error: 'invalid request' });
  }
  expect(seen).toHaveLength(1);
  expect(seen[0]!.aborted).toBe(false);
  c.socket.destroy();
  await vi.waitFor(() => expect(seen[0]!.aborted).toBe(true));
});

test('createProject takes one plain folder name and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"createProject","name":"my-app.2"}')).toEqual({ id: 1, ok: true, data: { folder: '/projects/local/my-app.2' } });
  const bad = ['""', '"."', '".."', '".hidden"', '"a/b"', '"../x"', '"-x"', '"a b"', `"${'a'.repeat(101)}"`, '7'];
  for (const [index, name] of bad.entries()) expect(await c.ask(`{"id":${index + 2},"cmd":"createProject","name":${name}}`)).toEqual({ id: index + 2, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":20,"cmd":"createProject"}')).toEqual({ id: 20, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":21,"cmd":"createProject","name":"a","force":true}')).toEqual({ id: 21, ok: false, error: 'invalid request' });
  expect(await c.ask(`{"id":22,"cmd":"createProject","name":"${'a'.repeat(100)}"}`)).toMatchObject({ ok: true });
});

test('githubRepos takes a page from 1 to 100 and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"githubRepos","page":1}')).toEqual({ id: 1, ok: true, data: { page: 1 } });
  expect(await c.ask('{"id":2,"cmd":"githubRepos","page":100}')).toEqual({ id: 2, ok: true, data: { page: 100 } });
  const bad = ['0', '101', '-1', '1.5', '"2"', 'null', 'true'];
  for (const [index, page] of bad.entries()) expect(await c.ask(`{"id":${index + 3},"cmd":"githubRepos","page":${page}}`)).toEqual({ id: index + 3, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":20,"cmd":"githubRepos"}')).toEqual({ id: 20, ok: false, error: 'invalid request' });
  expect(await c.ask('{"id":21,"cmd":"githubRepos","page":1,"filter":"push"}')).toEqual({ id: 21, ok: false, error: 'invalid request' });
});

test('a line that is not JSON is "invalid JSON" and the connection goes on', async () => {
  await open();
  const c = await client();
  expect(await c.ask('nope')).toEqual({ id: null, ok: false, error: 'invalid JSON' });
  expect(await c.ask('{"id":1,"cmd":"list"}')).toMatchObject({ ok: true });
});

test('a line over 1 MiB closes the connection with "line too long", and one under it is read', async () => {
  await open();
  const ok = await client();
  expect(await ok.ask(JSON.stringify({ id: 1, cmd: 'list', pad: 'x'.repeat(500 * 1024) }))).toMatchObject({ id: 1, ok: false, error: 'invalid request' }); // read in full, rejected as a request
  const c = await client();
  c.socket.write(`${'x'.repeat(1024 * 1024 + 1)}\n`);
  expect(await c.next()).toEqual({ id: null, ok: false, error: 'line too long' });
  await vi.waitFor(() => expect(c.isClosed()).toBe(true));
});

test('a refusal reaches the client in words, any other failure is only "internal error", and replies keep the order of the requests', async () => {
  await open();
  const c = await client();
  c.socket.write(`${JSON.stringify({ id: 1, cmd: 'open', agent: 'claude', folder: '/nope' })}\n${JSON.stringify({ id: 2, cmd: 'send', sessionId: uuid, text: 'hi' })}\n${JSON.stringify({ id: 3, cmd: 'events', sessionId: uuid, after: 5, limit: 10 })}\n`);
  expect(await c.next()).toEqual({ id: 1, ok: false, error: 'That folder does not exist' });
  expect(await c.next()).toEqual({ id: 2, ok: false, error: 'internal error' });
  expect(await c.next()).toEqual({ id: 3, ok: true, data: { after: 5 } });
});

test('stop replies ok and then runs the stop', async () => {
  const stop = vi.fn(async () => {});
  await open({ stop });
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"stop"}')).toEqual({ id: 1, ok: true });
  await vi.waitFor(() => expect(stop).toHaveBeenCalledTimes(1));
});

test('the host is told when a client joins and when it leaves', async () => {
  const events: string[] = [];
  await open({ clients: { joined: () => void events.push('joined'), left: () => void events.push('left') } });
  const c = await client();
  expect(events).toEqual(['joined']);
  c.socket.destroy();
  await vi.waitFor(() => expect(events).toEqual(['joined', 'left']));
});

test('close removes the socket file', async () => {
  await open();
  closers.pop()!();
  expect(() => statSync(join(dir, 'chat.sock'))).toThrow();
});
