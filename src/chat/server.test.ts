import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { connect, type Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { chatConfigPathOf, projectsPathOf } from '../config/places.ts';
import { editChatSettings } from './config.ts';
import { projectEdits } from './project-edits.ts';
import { ChatRefused, textCode } from './runner.ts';
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
    throw new ChatRefused('folder.notFound', 'That folder does not exist');
  },
  openPlan: async ({ plan }) => ({ session: { agent: plan.agent, state: 'preparing' } }),
  retryPreparation: async ({ sessionId }) => ({ retried: sessionId }),
  cancelPreparation: async ({ sessionId }) => {
    if (sessionId === '00000000-0000-4000-8000-000000000000') throw new ChatRefused('session.notPreparing', 'This session is not being prepared, so there is nothing to cancel');
    return { plan: { text: 'hi' } };
  },
  resume: async () => ({}),
  send: () => {
    throw new Error('the disk says secret things');
  },
  answer: ({ approvalId, choiceId }) => ({ approvalId, choiceId }),
  interrupt: async () => ({}),
  switchAgent: async ({ sessionId, agent }) => {
    if (agent === 'busy') throw new ChatRefused('session.busy', 'This session is working; interrupt it or wait, then switch its agent');
    return { session: { id: sessionId, agent }, options: [] };
  },
  stopTask: async ({ sessionId, taskId }) => ({ sessionId, taskId }),
  setOption: async ({ option, value }) => ({ option, value }),
  agentOptions: async ({ agent }) => ({ agent }),
  events: ({ after = 0, reasoning, lists }) => ({ after, ...(reasoning !== undefined && { reasoning }), ...(lists !== undefined && { lists }) }),
  close: async () => ({}),
  archive: async ({ archived }) => ({ archived }),
  delete: async () => ({}),
  rename: ({ title }) => ({ title }),
  regenerateTitle: async ({ sessionId }) => {
    if (sessionId === '00000000-0000-4000-8000-000000000000') throw new ChatRefused('title.noGenerator', 'Could not write a title: no text generator is chosen; choose one in Providers');
    return { title: 'A generated title' };
  },
  regenerateTitles: () => {
    if (refuseBulkTitles) throw new ChatRefused('title.noGenerator', 'Could not write titles: no text generator is chosen; choose one in Providers');
    return { started: 3 };
  },
  deletePreview: async ({ sessionIds }) => ({ sessionIds }),
  workspace: async ({ folder }) => ({ folder }),
  fetch: async ({ folder }) => ({ folder, fetched: true }),
  suggestName: async ({ folder }) => ({ name: `named-in-${folder}` }),
  checkName: async ({ name }) => ({ valid: true, free: true, name }),
  cloneRepo: async ({ repo }, gone) => {
    seen.push(gone);
    return { repo };
  },
  cloneProject: ({ repo, parent }) => {
    if (repo === 'acme/missing') throw new ChatRefused('project.exists', 'acme/missing is already a project', { repo: 'acme/missing' });
    return { repo, folder: `${parent ?? '/projects'}/${repo}`, state: 'cloning' };
  },
  projectClones: () => ({ clones: [{ repo: 'acme/app', folder: '/projects/acme/app', state: 'cloning', progress: 'Receiving objects: 45%' }] }),
  projectWorktrees: async ({ folder }) => {
    if (folder === '/gone') throw new ChatRefused('folder.notFound', 'That folder does not exist');
    return { main: { path: folder, branch: 'main', state: 'clean' }, worktrees: [{ path: '/home/chat/worktrees/acme/app/kerrigan', branch: 'carrier/kerrigan', session: null, lastActiveAt: 1000, state: 'clean' }] };
  },
  projectDisk: ({ folders, refresh }) => ({ projects: folders.map((folder) => ({ folder, bytes: 2048, measuredAt: 5, parts: { [folder]: 2048 } })), measuring: refresh === 'now' ? folders : [] }),
  removeProjectWorktree: async ({ path }) => {
    if (path === '/open') throw new ChatRefused('worktree.sessionOpen', 'Its session is open');
    return {};
  },
  cleanProjectWorktrees: async ({ run }) => ({ removed: [{ path: '/w/a', bytes: run ? 2048 : 1024 }], skipped: [{ path: '/w/b', reason: 'It has uncommitted changes' }] }),
  dismissClone: () => ({ clones: [] }),
  newProject: async ({ name, parent }) => {
    if (name === 'taken') throw new ChatRefused('project.nameTaken', 'taken is already a project; choose another name', { name: 'taken' });
    return { folder: `${parent ?? '/projects'}/local/${name}` };
  },
  createProject: async ({ name }) => ({ folder: `/projects/local/${name}` }),
  githubRepos: async ({ page }) => ({ page }),
  repoBranches: async ({ repo }) => ({ repo }),
  health: async ({ refresh }) => ({ refresh }),
  providers: async () => ({ accounts: [] }),
  usage: async (args) => ({ args }),
  usageOverride: (args) => {
    if (args.model === 'refused') throw new ChatRefused('usage.priceInvalid', 'That price cannot be saved', { model: 'refused' });
    return { args };
  },
  // the real writing code, over a scratch Carrier folder
  editChatSettings: ({ changes }) => editChatSettings(changes, home()),
  addProject: (args) => projectEdits.addProject(args, home()),
  removeProject: (args) => projectEdits.removeProject(args, home()),
  editProject: (args) => projectEdits.editProject(args, home()),
  moveProject: (args) => projectEdits.moveProject(args, home()),
  editProjectIcon: (args) => projectEdits.editProjectIcon(args, home()),
  editProjectDefaults: (args) => projectEdits.editProjectDefaults(args, home()),
  editProjectTags: (args) => projectEdits.editProjectTags(args, home()),
  setProjectActions: (args) => projectEdits.setProjectActions(args, home()),
  setProjectsFolder: (args) => projectEdits.setProjectsFolder(args, home()),
});
const seen: AbortSignal[] = [];
let refuseBulkTitles = false;
async function open({ stop = async () => {}, clients = noClients } = {}) {
  refuseBulkTitles = false;
  const server = await startChatServer({ stateDir: dir, startedAt: 1234, controls: controls(), stop, clients });
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
  expect(c.hello).toMatchObject({ event: 'hello', protocol: 1, pid: process.pid, startedAt: 1234, capabilities: ['agents', 'list', 'open', 'resume', 'send', 'answer', 'interrupt', 'setOption', 'agentOptions', 'events', 'close', 'archive', 'delete', 'workspace', 'fetch', 'suggestName', 'checkName', 'deletePreview', 'cloneRepo', 'createProject', 'githubRepos', 'repoBranches', 'health', 'providers', 'plan', 'stop', 'reasoning', 'rename', 'usage', 'usageOverride', 'accountIdentity', 'accountPalette', 'switchAgent', 'stopTask', 'worktreeStart', 'fetchIfStale', 'listsRev', 'projects', 'textGenerators', 'regenerateTitle', 'regenerateTitles', 'config'] });
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
  ['a health refresh that is not a boolean', '{"id":8,"cmd":"health","refresh":"yes"}', 8],
  ['a health with an extra field', '{"id":10,"cmd":"health","agent":"claude"}', 10],
  ['providers with a field', '{"id":12,"cmd":"providers","refresh":true}', 12],
  ['events with a lists that is not a string', `{"id":50,"cmd":"events","sessionId":"${uuid}","limit":10,"lists":7}`, 50],
  ['events with an empty lists', `{"id":51,"cmd":"events","sessionId":"${uuid}","limit":10,"lists":""}`, 51],
  ['events asking for reasoning with a non-boolean', `{"id":11,"cmd":"events","sessionId":"${uuid}","limit":10,"reasoning":"yes"}`, 11],
  ['usage with a range that is not offered', '{"id":20,"cmd":"usage","days":10}', 20],
  ['usage with a provider that is not one', '{"id":21,"cmd":"usage","provider":"gemini"}', 21],
  ['usage with a source that is not one', '{"id":22,"cmd":"usage","source":"cli"}', 22],
  ['usage with an extra field', '{"id":23,"cmd":"usage","force":true}', 23],
  ['usage with an empty account', '{"id":24,"cmd":"usage","account":" "}', 24],
  ['an override with an unknown action', '{"id":25,"cmd":"usageOverride","model":"m","action":"free"}', 25],
  ['an override with no model', '{"id":26,"cmd":"usageOverride","action":"clear"}', 26],
  ['an alias with no target', '{"id":27,"cmd":"usageOverride","model":"m","action":"alias"}', 27],
  ['a custom price with no output rate', '{"id":28,"cmd":"usageOverride","model":"m","action":"custom","inputPerMillionUsd":1}', 28],
  ['a custom price with a negative rate', '{"id":29,"cmd":"usageOverride","model":"m","action":"custom","inputPerMillionUsd":-1,"outputPerMillionUsd":1}', 29],
  ['a custom price with a rate over the limit', '{"id":30,"cmd":"usageOverride","model":"m","action":"custom","inputPerMillionUsd":1,"outputPerMillionUsd":10001}', 30],
  ['a custom price with a rate that is not a number', '{"id":31,"cmd":"usageOverride","model":"m","action":"custom","inputPerMillionUsd":"1","outputPerMillionUsd":1}', 31],
  ['an override with an extra field', '{"id":32,"cmd":"usageOverride","model":"m","action":"local","mode":"zero"}', 32],
  ['an override with an empty model', '{"id":33,"cmd":"usageOverride","model":"  ","action":"local"}', 33],
  ['a stopTask with no task id', `{"id":40,"cmd":"stopTask","sessionId":"${uuid}"}`, 40],
  ['a stopTask with an empty task id', `{"id":41,"cmd":"stopTask","sessionId":"${uuid}","taskId":""}`, 41],
  ['a stopTask with a task id that is not a string', `{"id":42,"cmd":"stopTask","sessionId":"${uuid}","taskId":7}`, 42],
  ['a stopTask with a session id that is not one', '{"id":43,"cmd":"stopTask","sessionId":"../x","taskId":"a"}', 43],
  ['a stopTask with an extra field', `{"id":44,"cmd":"stopTask","sessionId":"${uuid}","taskId":"a","force":true}`, 44],
  ['a missing id', '{"cmd":"list"}', null],
  ['a bad id', '{"id":-1,"cmd":"list"}', null],
])('%s is "invalid request", with the id only when it is valid', async (_name, line, id) => {
  await open();
  const c = await client();
  expect(await c.ask(line)).toEqual({ id, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":9,"cmd":"list"}')).toMatchObject({ id: 9, ok: true });
});

test('events takes the lists revision the client has and passes it on', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"events","sessionId":"${uuid}","limit":10,"lists":"abc123"}`)).toEqual({ id: 1, ok: true, data: { after: 0, lists: 'abc123' } });
});

test('events takes an optional reasoning and passes it on', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"events","sessionId":"${uuid}","limit":10}`)).toEqual({ id: 1, ok: true, data: { after: 0 } });
  expect(await c.ask(`{"id":2,"cmd":"events","sessionId":"${uuid}","limit":10,"reasoning":true}`)).toEqual({ id: 2, ok: true, data: { after: 0, reasoning: true } });
});

test('health takes an optional refresh and passes it on', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"health"}')).toEqual({ id: 1, ok: true, data: {} });
  expect(await c.ask('{"id":2,"cmd":"health","refresh":true}')).toEqual({ id: 2, ok: true, data: { refresh: true } });
});

test('usage passes its filters on, and an override reaches the controls with the words of a refusal', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"usage"}')).toEqual({ id: 1, ok: true, data: { args: {} } });
  expect(await c.ask('{"id":2,"cmd":"usage","refresh":true,"days":7,"provider":"local","source":"chat","search":" opus ","account":"claude-work"}')).toEqual({ id: 2, ok: true, data: { args: { refresh: true, days: 7, provider: 'local', source: 'chat', search: 'opus', account: 'claude-work' } } });
  expect(await c.ask('{"id":3,"cmd":"usageOverride","model":"qwen","action":"local"}')).toEqual({ id: 3, ok: true, data: { args: { model: 'qwen', action: 'local' } } });
  expect(await c.ask('{"id":4,"cmd":"usageOverride","model":"qwen","action":"alias","aliasTo":"gpt-5"}')).toMatchObject({ ok: true, data: { args: { aliasTo: 'gpt-5' } } });
  expect(await c.ask('{"id":5,"cmd":"usageOverride","model":"qwen","action":"custom","inputPerMillionUsd":0,"outputPerMillionUsd":2.5,"cacheWritePerMillionUsd":1}')).toMatchObject({ ok: true, data: { args: { inputPerMillionUsd: 0, outputPerMillionUsd: 2.5, cacheWritePerMillionUsd: 1 } } });
  expect(await c.ask('{"id":6,"cmd":"usageOverride","model":"refused","action":"clear"}')).toEqual({ id: 6, ok: false, error: 'That price cannot be saved', code: 'usage.priceInvalid', params: { model: 'refused' } });
});

test('stopTask passes the session and the task on', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"stopTask","sessionId":"${uuid}","taskId":"af0d8b127fea03930"}`)).toEqual({ id: 1, ok: true, data: { sessionId: uuid, taskId: 'af0d8b127fea03930' } });
});

test('answer is a strict request with a session, an approval and a choice', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"answer","sessionId":"${uuid}","approvalId":"a","choiceId":"deny"}`)).toEqual({ id: 1, ok: true, data: { approvalId: 'a', choiceId: 'deny' } });
});

test('answer takes the answers to a question approval: at most four, text only', async () => {
  await open();
  const c = await client();
  const base = `{"id":1,"cmd":"answer","sessionId":"${uuid}","approvalId":"a","choiceId":"allow"`;
  expect(await c.ask(`${base},"answers":{"Which?":"A"}}`)).toMatchObject({ ok: true, data: { approvalId: 'a', choiceId: 'allow' } });
  expect(await c.ask(`${base},"answers":{"Which?":1}}`)).toMatchObject({ ok: false });
  expect(await c.ask(`${base},"answers":{"1":"a","2":"a","3":"a","4":"a","5":"a"}}`)).toMatchObject({ ok: false });
});

test('send takes a message, or a command with or without a message, and nothing empty', async () => {
  await open();
  const c = await client();
  // the controls of this file fail every send: a valid request gets that failure and an invalid one is refused before it
  const refused = async (request: string) => (await c.ask(request)).error === 'invalid request';
  expect(await refused(`{"id":1,"cmd":"send","sessionId":"${uuid}","text":"hi"}`)).toBe(false);
  expect(await refused(`{"id":2,"cmd":"send","sessionId":"${uuid}","text":"hi","command":"review"}`)).toBe(false);
  expect(await refused(`{"id":3,"cmd":"send","sessionId":"${uuid}","text":"","command":"review"}`)).toBe(false);
  expect(await refused(`{"id":4,"cmd":"send","sessionId":"${uuid}","text":""}`)).toBe(true);
  expect(await refused(`{"id":5,"cmd":"send","sessionId":"${uuid}","text":"hi","command":""}`)).toBe(true);
});

test('agentOptions takes the name of an agent and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"agentOptions","agent":"claude"}')).toEqual({ id: 1, ok: true, data: { agent: 'claude' } });
  expect(await c.ask('{"id":2,"cmd":"agentOptions"}')).toEqual({ id: 2, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":3,"cmd":"agentOptions","agent":""}')).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":4,"cmd":"agentOptions","agent":"claude","folder":"/"}')).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('setOption is a strict request with a session, an option and a value', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"setOption","sessionId":"${uuid}","option":"model","value":"haiku"}`)).toEqual({ id: 1, ok: true, data: { option: 'model', value: 'haiku' } });
  expect(await c.ask(`{"id":2,"cmd":"setOption","sessionId":"${uuid}","option":"model"}`)).toEqual({ id: 2, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('archive takes a session and a boolean, delete a session, both strict', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"archive","sessionId":"${uuid}","archived":true}`)).toEqual({ id: 1, ok: true, data: { archived: true } });
  expect(await c.ask(`{"id":2,"cmd":"archive","sessionId":"${uuid}"}`)).toEqual({ id: 2, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask(`{"id":3,"cmd":"delete","sessionId":"${uuid}"}`)).toEqual({ id: 3, ok: true, data: {} });
  expect(await c.ask(`{"id":4,"cmd":"delete","sessionId":"${uuid}","archived":true}`)).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('switchAgent takes a session and the name of an agent, strict, and a refusal reaches the client in words', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"switchAgent","sessionId":"${uuid}","agent":"codex"}`)).toEqual({ id: 1, ok: true, data: { session: { id: uuid, agent: 'codex' }, options: [] } });
  expect(await c.ask(`{"id":2,"cmd":"switchAgent","sessionId":"${uuid}","agent":"busy"}`)).toEqual({ id: 2, ok: false, error: 'This session is working; interrupt it or wait, then switch its agent', code: 'session.busy', params: {} });
  expect(await c.ask(`{"id":3,"cmd":"switchAgent","sessionId":"${uuid}"}`)).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask(`{"id":4,"cmd":"switchAgent","sessionId":"${uuid}","agent":""}`)).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":5,"cmd":"switchAgent","sessionId":"../x","agent":"codex"}')).toEqual({ id: 5, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask(`{"id":6,"cmd":"switchAgent","sessionId":"${uuid}","agent":"codex","options":{}}`)).toEqual({ id: 6, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('rename takes a session and a title, strict', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"rename","sessionId":"${uuid}","title":"New name"}`)).toEqual({ id: 1, ok: true, data: { title: 'New name' } });
  expect(await c.ask(`{"id":2,"cmd":"rename","sessionId":"${uuid}"}`)).toEqual({ id: 2, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask(`{"id":3,"cmd":"rename","sessionId":"${uuid}","title":"x","archived":true}`)).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('regenerateTitle takes a session id, strict, and a refusal reaches the client in its words', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"regenerateTitle","sessionId":"${uuid}"}`)).toEqual({ id: 1, ok: true, data: { title: 'A generated title' } });
  expect(await c.ask('{"id":2,"cmd":"regenerateTitle","sessionId":"00000000-0000-4000-8000-000000000000"}')).toEqual({ id: 2, ok: false, error: 'Could not write a title: no text generator is chosen; choose one in Providers', code: 'title.noGenerator', params: {} });
  expect(await c.ask('{"id":3,"cmd":"regenerateTitle"}')).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":4,"cmd":"regenerateTitle","sessionId":"../x"}')).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask(`{"id":5,"cmd":"regenerateTitle","sessionId":"${uuid}","title":"x"}`)).toEqual({ id: 5, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('regenerateTitles takes no fields, answers how many it started, and a refusal reaches the client in its words', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"regenerateTitles"}')).toEqual({ id: 1, ok: true, data: { started: 3 } });
  expect(await c.ask(`{"id":2,"cmd":"regenerateTitles","sessionId":"${uuid}"}`)).toEqual({ id: 2, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  refuseBulkTitles = true;
  expect(await c.ask('{"id":3,"cmd":"regenerateTitles"}')).toEqual({ id: 3, ok: false, error: 'Could not write titles: no text generator is chosen; choose one in Providers', code: 'title.noGenerator', params: {} });
});

test('deletePreview takes one to 500 session ids and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"deletePreview","sessionIds":["${uuid}"]}`)).toEqual({ id: 1, ok: true, data: { sessionIds: [uuid] } });
  expect(await c.ask(`{"id":2,"cmd":"deletePreview","sessionIds":${JSON.stringify(Array(500).fill(uuid))}}`)).toMatchObject({ id: 2, ok: true });
  expect(await c.ask(`{"id":3,"cmd":"deletePreview","sessionIds":${JSON.stringify(Array(501).fill(uuid))}}`)).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":4,"cmd":"deletePreview","sessionIds":[]}')).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":5,"cmd":"deletePreview","sessionIds":["../x"]}')).toEqual({ id: 5, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":6,"cmd":"deletePreview"}')).toEqual({ id: 6, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask(`{"id":7,"cmd":"deletePreview","sessionIds":["${uuid}"],"force":true}`)).toEqual({ id: 7, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('workspace takes a folder and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"workspace","folder":"/some/where"}')).toEqual({ id: 1, ok: true, data: { folder: '/some/where' } });
  expect(await c.ask('{"id":2,"cmd":"workspace"}')).toEqual({ id: 2, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":3,"cmd":"workspace","folder":""}')).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":4,"cmd":"workspace","folder":"/x","fetch":true}')).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('fetch takes a folder and an optional boolean ifStale, and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"fetch","folder":"/some/where"}')).toEqual({ id: 1, ok: true, data: { folder: '/some/where', fetched: true } });
  expect(await c.ask('{"id":2,"cmd":"fetch"}')).toEqual({ id: 2, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":3,"cmd":"fetch","folder":""}')).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":4,"cmd":"fetch","folder":"/x","prune":false}')).toEqual({ id: 4, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  for (const ifStale of [true, false]) expect(await c.ask(`{"id":5,"cmd":"fetch","folder":"/x","ifStale":${ifStale}}`)).toMatchObject({ ok: true });
  for (const ifStale of ['"true"', '1', 'null', '{}']) expect(await c.ask(`{"id":6,"cmd":"fetch","folder":"/x","ifStale":${ifStale}}`)).toEqual({ id: 6, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('suggestName takes a folder, checkName a folder and a name, and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"suggestName","folder":"/some/where"}')).toEqual({ id: 1, ok: true, data: { name: 'named-in-/some/where' } });
  expect(await c.ask('{"id":2,"cmd":"suggestName"}')).toEqual({ id: 2, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":3,"cmd":"suggestName","folder":"/x","name":"a"}')).toEqual({ id: 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":4,"cmd":"checkName","folder":"/x","name":"a-b"}')).toEqual({ id: 4, ok: true, data: { valid: true, free: true, name: 'a-b' } });
  expect(await c.ask('{"id":5,"cmd":"checkName","folder":"/x"}')).toEqual({ id: 5, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":6,"cmd":"checkName","name":"a"}')).toEqual({ id: 6, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":7,"cmd":"checkName","folder":"","name":"a"}')).toEqual({ id: 7, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":8,"cmd":"checkName","folder":"/x","name":1}')).toEqual({ id: 8, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":9,"cmd":"checkName","folder":"/x","name":"a","force":true}')).toEqual({ id: 9, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('cloneRepo takes one owner/name repo and nothing else, and its signal aborts when the client leaves', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"cloneRepo","repo":"acme/app"}')).toEqual({ id: 1, ok: true, data: { repo: 'acme/app' } });
  for (const [id, extra] of [[2, ''], [3, ',"repo":""'], [4, ',"repo":"../x"'], [5, ',"repo":"a/..'], [6, ',"repo":"a/b/c"'], [7, ',"repo":"solo"'], [8, ',"repo":7'], [9, ',"repo":"a/b","force":true']] as const) {
    expect(await c.ask(`{"id":${id},"cmd":"cloneRepo"${extra}${id === 5 ? '"' : ''}}`)).toEqual({ id, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
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
  for (const [index, name] of bad.entries()) expect(await c.ask(`{"id":${index + 2},"cmd":"createProject","name":${name}}`)).toEqual({ id: index + 2, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":20,"cmd":"createProject"}')).toEqual({ id: 20, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":21,"cmd":"createProject","name":"a","force":true}')).toEqual({ id: 21, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask(`{"id":22,"cmd":"createProject","name":"${'a'.repeat(100)}"}`)).toMatchObject({ ok: true });
});

test('the projects requests: a clone starts and answers at once, the clones in flight are listed, a failed one is dismissed', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"cloneProject","repo":"acme/app"}')).toEqual({ id: 1, ok: true, data: { repo: 'acme/app', folder: '/projects/acme/app', state: 'cloning' } });
  expect(await c.ask('{"id":2,"cmd":"cloneProject","repo":"acme/app","parent":"/work"}')).toMatchObject({ ok: true, data: { folder: '/work/acme/app' } });
  expect(await c.ask('{"id":3,"cmd":"cloneProject","repo":"acme/missing"}')).toEqual({ id: 3, ok: false, error: 'acme/missing is already a project', code: 'project.exists', params: { repo: 'acme/missing' } });
  expect(await c.ask('{"id":4,"cmd":"projectClones"}')).toEqual({ id: 4, ok: true, data: { clones: [{ repo: 'acme/app', folder: '/projects/acme/app', state: 'cloning', progress: 'Receiving objects: 45%' }] } });
  expect(await c.ask('{"id":5,"cmd":"dismissClone","repo":"acme/app"}')).toEqual({ id: 5, ok: true, data: { clones: [] } });
  const bad = [
    '{"id":10,"cmd":"cloneProject"}',
    '{"id":11,"cmd":"cloneProject","repo":"../x"}',
    '{"id":12,"cmd":"cloneProject","repo":"a/b","parent":""}',
    '{"id":13,"cmd":"cloneProject","repo":"a/b","force":true}',
    '{"id":14,"cmd":"projectClones","repo":"a/b"}',
    '{"id":15,"cmd":"dismissClone"}',
    '{"id":16,"cmd":"dismissClone","repo":"a/b/c"}',
  ];
  for (const line of bad) expect(await c.ask(line)).toMatchObject({ ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('projectWorktrees takes a folder and nothing else, and answers the main clone and the worktrees', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"projectWorktrees","folder":"/work/app"}')).toEqual({ id: 1, ok: true, data: { main: { path: '/work/app', branch: 'main', state: 'clean' }, worktrees: [{ path: '/home/chat/worktrees/acme/app/kerrigan', branch: 'carrier/kerrigan', session: null, lastActiveAt: 1000, state: 'clean' }] } });
  expect(await c.ask('{"id":2,"cmd":"projectWorktrees","folder":"/gone"}')).toEqual({ id: 2, ok: false, error: 'That folder does not exist', code: 'folder.notFound', params: {} });
  const bad = ['{"id":10,"cmd":"projectWorktrees"}', '{"id":11,"cmd":"projectWorktrees","folder":""}', '{"id":12,"cmd":"projectWorktrees","folder":"/a","force":true}', `{"id":13,"cmd":"projectWorktrees","folder":"/${'a'.repeat(4096)}"}`];
  for (const line of bad) expect(await c.ask(line)).toMatchObject({ ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('projectDisk takes one to 500 folders and a refresh of stale or now, and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"projectDisk","folders":["/work/app"]}')).toEqual({ id: 1, ok: true, data: { projects: [{ folder: '/work/app', bytes: 2048, measuredAt: 5, parts: { '/work/app': 2048 } }], measuring: [] } });
  expect(await c.ask('{"id":2,"cmd":"projectDisk","folders":["/work/app"],"refresh":"now"}')).toMatchObject({ ok: true, data: { measuring: ['/work/app'] } });
  const many = JSON.stringify(Array.from({ length: 500 }, (_, index) => `/w/${index}`));
  expect(await c.ask(`{"id":3,"cmd":"projectDisk","folders":${many}}`)).toMatchObject({ ok: true });
  const bad = ['{"id":10,"cmd":"projectDisk"}', '{"id":11,"cmd":"projectDisk","folders":[]}', '{"id":12,"cmd":"projectDisk","folders":[""]}', '{"id":13,"cmd":"projectDisk","folders":["/a"],"refresh":"always"}', '{"id":14,"cmd":"projectDisk","folders":["/a"],"force":true}', `{"id":15,"cmd":"projectDisk","folders":${JSON.stringify(Array.from({ length: 501 }, () => '/a'))}}`, `{"id":16,"cmd":"projectDisk","folders":["/${'a'.repeat(4096)}"]}`, '{"id":17,"cmd":"projectDisk","folders":"/a"}'];
  for (const line of bad) expect(await c.ask(line)).toMatchObject({ ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('removeProjectWorktree takes a project folder and a worktree path, and cleanProjectWorktrees a folder and whether to run', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"removeProjectWorktree","folder":"/work/app","path":"/w/a"}')).toEqual({ id: 1, ok: true, data: {} });
  expect(await c.ask('{"id":2,"cmd":"removeProjectWorktree","folder":"/work/app","path":"/open"}')).toEqual({ id: 2, ok: false, error: 'Its session is open', code: 'worktree.sessionOpen', params: {} });
  const removed = [{ path: '/w/a', bytes: 1024 }];
  const skipped = [{ path: '/w/b', reason: 'It has uncommitted changes' }];
  // asking without `run` only says what would go; the answer to `run` is what went
  expect(await c.ask('{"id":3,"cmd":"cleanProjectWorktrees","folder":"/work/app"}')).toEqual({ id: 3, ok: true, data: { removed, skipped } });
  expect(await c.ask('{"id":4,"cmd":"cleanProjectWorktrees","folder":"/work/app","run":true}')).toEqual({ id: 4, ok: true, data: { removed: [{ path: '/w/a', bytes: 2048 }], skipped } });
  const bad = [
    '{"id":10,"cmd":"removeProjectWorktree","folder":"/a"}',
    '{"id":11,"cmd":"removeProjectWorktree","path":"/a"}',
    '{"id":12,"cmd":"removeProjectWorktree","folder":"","path":"/a"}',
    '{"id":13,"cmd":"removeProjectWorktree","folder":"/a","path":"/b","force":true}',
    `{"id":14,"cmd":"removeProjectWorktree","folder":"/a","path":"/${'a'.repeat(4096)}"}`,
    '{"id":15,"cmd":"cleanProjectWorktrees"}',
    '{"id":16,"cmd":"cleanProjectWorktrees","folder":"/a","run":"yes"}',
    '{"id":17,"cmd":"cleanProjectWorktrees","folder":"/a","run":true,"force":true}',
  ];
  for (const line of bad) expect(await c.ask(line)).toMatchObject({ ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('newProject takes a plain folder name and an optional parent, and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"newProject","name":"my-app"}')).toEqual({ id: 1, ok: true, data: { folder: '/projects/local/my-app' } });
  expect(await c.ask('{"id":2,"cmd":"newProject","name":"my-app","parent":"/work"}')).toEqual({ id: 2, ok: true, data: { folder: '/work/local/my-app' } });
  expect(await c.ask('{"id":3,"cmd":"newProject","name":"taken"}')).toEqual({ id: 3, ok: false, error: 'taken is already a project; choose another name', code: 'project.nameTaken', params: { name: 'taken' } });
  const bad = [
    '{"id":10,"cmd":"newProject"}',
    '{"id":11,"cmd":"newProject","name":"a/b"}',
    '{"id":12,"cmd":"newProject","name":".hidden"}',
    '{"id":13,"cmd":"newProject","name":"a","parent":""}',
    '{"id":14,"cmd":"newProject","name":"a","force":true}',
  ];
  for (const line of bad) expect(await c.ask(line)).toMatchObject({ ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

const planOf = (extra: object = {}, workspace: object = { kind: 'folder', folder: '/work' }) => JSON.stringify({ id: 1, cmd: 'open', plan: { workspace, agent: 'claude', text: 'hi', ...extra } });

test('open takes a plan, strictly: what it refuses and what it accepts', async () => {
  await open();
  const c = await client();
  expect(await c.ask(planOf())).toEqual({ id: 1, ok: true, data: { session: { agent: 'claude', state: 'preparing' } } });
  for (const branch of ['main', 'feat/x']) expect(await c.ask(planOf({ branch }))).toMatchObject({ ok: true });
  expect(await c.ask(planOf({ options: { model: 'haiku' }, worktree: { name: 'mine' } }))).toMatchObject({ ok: true });
  for (const startFrom of ['remote', 'local']) expect(await c.ask(planOf({ branch: 'main', worktree: { startFrom } }))).toMatchObject({ ok: true });
  expect(await c.ask(planOf({}, { kind: 'repo', repo: 'AshuLab/carrier' }))).toMatchObject({ ok: true });
  expect(await c.ask(planOf({}, { kind: 'project', name: 'my-app' }))).toMatchObject({ ok: true });
  const bad: [string, string][] = [
    ['an empty text', planOf({ text: '' })],
    ['a branch with a leading dash', planOf({ branch: '-x' })],
    ['a branch with a space', planOf({ branch: 'a b' })],
    ['an empty branch', planOf({ branch: '' })],
    ['a repo that climbs', planOf({}, { kind: 'repo', repo: 'a/../b' })],
    ['an empty repo', planOf({}, { kind: 'repo', repo: '' })],
    ['a project with a branch', planOf({ branch: 'main' }, { kind: 'project', name: 'my-app' })],
    ['a project with a worktree', planOf({ worktree: {} }, { kind: 'project', name: 'my-app' })],
    ['a worktree start that is neither remote nor local', planOf({ branch: 'main', worktree: { startFrom: 'origin' } })],
    ['a worktree start that is not a text', planOf({ branch: 'main', worktree: { startFrom: true } })],
    ['an unknown workspace kind', planOf({}, { kind: 'url', url: 'x' })],
    ['an extra field of the plan', planOf({ force: true })],
    ['a plan together with a folder', JSON.stringify({ id: 1, cmd: 'open', folder: '/work', plan: { workspace: { kind: 'folder', folder: '/work' }, agent: 'claude', text: 'hi' } })],
    ['a plan together with an agent', JSON.stringify({ id: 1, cmd: 'open', agent: 'claude', plan: { workspace: { kind: 'folder', folder: '/work' }, agent: 'claude', text: 'hi' } })],
  ];
  for (const [what, line] of bad) expect(await c.ask(line), what).toEqual({ id: 1, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  // the old open is still the old open
  expect(await c.ask('{"id":2,"cmd":"open","agent":"claude","folder":"/nope"}')).toEqual({ id: 2, ok: false, error: 'That folder does not exist', code: 'folder.notFound', params: {} });
});

test('retryPreparation and cancelPreparation take a session id and nothing else, and a refusal reaches the client in words', async () => {
  await open();
  const c = await client();
  const sessionId = '11111111-1111-4111-8111-111111111111';
  expect(await c.ask(`{"id":1,"cmd":"retryPreparation","sessionId":"${sessionId}"}`)).toEqual({ id: 1, ok: true, data: { retried: sessionId } });
  expect(await c.ask(`{"id":2,"cmd":"cancelPreparation","sessionId":"${sessionId}"}`)).toEqual({ id: 2, ok: true, data: { plan: { text: 'hi' } } });
  expect(await c.ask('{"id":3,"cmd":"cancelPreparation","sessionId":"00000000-0000-4000-8000-000000000000"}')).toEqual({ id: 3, ok: false, error: 'This session is not being prepared, so there is nothing to cancel', code: 'session.notPreparing', params: {} });
  for (const cmd of ['retryPreparation', 'cancelPreparation']) {
    for (const [what, fields] of [['no id', ''], ['an id that is not a UUID', ',"sessionId":"x"'], ['an extra field', `,"sessionId":"${sessionId}","force":true`]] as const) {
      expect(await c.ask(`{"id":9,"cmd":"${cmd}"${fields}}`), `${cmd} with ${what}`).toEqual({ id: 9, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
    }
  }
});

test('githubRepos takes a page from 1 to 100 and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"githubRepos","page":1}')).toEqual({ id: 1, ok: true, data: { page: 1 } });
  expect(await c.ask('{"id":2,"cmd":"githubRepos","page":100}')).toEqual({ id: 2, ok: true, data: { page: 100 } });
  const bad = ['0', '101', '-1', '1.5', '"2"', 'null', 'true'];
  for (const [index, page] of bad.entries()) expect(await c.ask(`{"id":${index + 3},"cmd":"githubRepos","page":${page}}`)).toEqual({ id: index + 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":20,"cmd":"githubRepos"}')).toEqual({ id: 20, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":21,"cmd":"githubRepos","page":1,"filter":"push"}')).toEqual({ id: 21, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('repoBranches takes one owner/name repo and nothing else', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"repoBranches","repo":"acme/app"}')).toEqual({ id: 1, ok: true, data: { repo: 'acme/app' } });
  const bad = ['""', '"../x"', '"a/b/c"', '"solo"', '7', 'null'];
  for (const [index, repo] of bad.entries()) expect(await c.ask(`{"id":${index + 3},"cmd":"repoBranches","repo":${repo}}`)).toEqual({ id: index + 3, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":20,"cmd":"repoBranches"}')).toEqual({ id: 20, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask('{"id":21,"cmd":"repoBranches","repo":"acme/app","page":1}')).toEqual({ id: 21, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
});

test('a line that is not JSON is "invalid JSON" and the connection goes on', async () => {
  await open();
  const c = await client();
  expect(await c.ask('nope')).toEqual({ id: null, ok: false, error: 'invalid JSON', code: 'request.invalidJson', params: {} });
  expect(await c.ask('{"id":1,"cmd":"list"}')).toMatchObject({ ok: true });
});

test('a line over 1 MiB closes the connection with "line too long", and one under it is read', async () => {
  await open();
  const ok = await client();
  expect(await ok.ask(JSON.stringify({ id: 1, cmd: 'list', pad: 'x'.repeat(500 * 1024) }))).toMatchObject({ id: 1, ok: false, error: 'invalid request', code: 'request.invalid', params: {} }); // read in full, rejected as a request
  const c = await client();
  c.socket.write(`${'x'.repeat(1024 * 1024 + 1)}\n`);
  expect(await c.next()).toEqual({ id: null, ok: false, error: 'line too long', code: 'request.tooLong', params: {} });
  await vi.waitFor(() => expect(c.isClosed()).toBe(true));
});

test('a refusal reaches the client in words, any other failure is only "internal error", and replies keep the order of the requests', async () => {
  await open();
  const c = await client();
  c.socket.write(`${JSON.stringify({ id: 1, cmd: 'open', agent: 'claude', folder: '/nope' })}\n${JSON.stringify({ id: 2, cmd: 'send', sessionId: uuid, text: 'hi' })}\n${JSON.stringify({ id: 3, cmd: 'events', sessionId: uuid, after: 5, limit: 10 })}\n`);
  expect(await c.next()).toEqual({ id: 1, ok: false, error: 'That folder does not exist', code: 'folder.notFound', params: {} });
  expect(await c.next()).toEqual({ id: 2, ok: false, error: 'internal error', code: 'request.internal', params: {} });
  expect(await c.next()).toEqual({ id: 3, ok: true, data: { after: 5 } });
});

test('a refusal answers its code and params beside its words, and the fixed errors carry none', async () => {
  await open();
  const c = await client();
  const refusals = [
    '{"id":1,"cmd":"open","agent":"claude","folder":"/nope"}',
    '{"id":2,"cmd":"cloneProject","repo":"acme/missing"}',
    '{"id":3,"cmd":"newProject","name":"taken"}',
    '{"id":4,"cmd":"usageOverride","model":"refused","action":"clear"}',
    `{"id":5,"cmd":"switchAgent","sessionId":"${uuid}","agent":"busy"}`,
  ];
  for (const line of refusals) {
    const reply = (await c.ask(line)) as { ok: boolean; error: string; code: string; params: Record<string, unknown> };
    expect(reply.ok).toBe(false);
    expect(reply.code).toMatch(textCode);
    for (const value of Object.values(reply.params)) expect(['string', 'number']).toContain(typeof value);
  }
  // the replies of the socket itself keep their words and gain nothing
  expect(await c.ask('not json')).toEqual({ id: null, ok: false, error: 'invalid JSON', code: 'request.invalidJson', params: {} });
  expect(await c.ask('{"id":6,"cmd":"nope"}')).toEqual({ id: 6, ok: false, error: 'invalid request', code: 'request.invalid', params: {} });
  expect(await c.ask(`{"id":7,"cmd":"send","sessionId":"${uuid}","text":"hi"}`)).toEqual({ id: 7, ok: false, error: 'internal error', code: 'request.internal', params: {} });
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

const home = () => join(dir, 'home'); // not there until a test or the writing code makes it
const settingsFile = () => chatConfigPathOf(home());
const seed = (text: string) => (mkdirSync(home()), writeFileSync(settingsFile(), text));
const edit = async (changes: object) => {
  await open();
  const c = await client();
  return c.ask(JSON.stringify({ id: 1, cmd: 'editChatSettings', changes }));
};

test('editChatSettings changes the keys it is given, keeps every other key as written, and a null removes one', async () => {
  const written = { projectsFolder: '/where/I/keep/them', agents: { me: { account: 'claude-work' } }, deleteAfterDays: 60, worktreeStart: 'local' };
  seed(JSON.stringify(written));
  expect(await edit({ archiveAfterDays: 7, worktreeStart: null, idleCloseMinutes: 30 })).toEqual({ id: 1, ok: true, data: { saved: { archiveAfterDays: 7, idleCloseMinutes: 30 } } });
  expect(JSON.parse(readFileSync(settingsFile(), 'utf8'))).toEqual({ projectsFolder: '/where/I/keep/them', agents: written.agents, deleteAfterDays: 60, archiveAfterDays: 7, idleCloseMinutes: 30 });
  expect(readdirSync(home()).filter((name) => name.endsWith('.tmp'))).toEqual([]);
});

test('editChatSettings makes a chat.json that is not there, with its folder', async () => {
  expect(await edit({ deleteAfterDays: 'never' })).toMatchObject({ ok: true, data: { saved: { deleteAfterDays: 'never' } } });
  expect(JSON.parse(readFileSync(settingsFile(), 'utf8'))).toEqual({ deleteAfterDays: 'never' });
});

test.each([
  [{ idleCloseMinutes: 15 }, 'idleCloseMinutes', 'invalid_union'],
  [{ deleteAfterDays: 10 }, 'deleteAfterDays', 'custom'],
  [{ archiveAfterDays: 0 }, 'archiveAfterDays', 'too_small'],
  [{ worktreeStart: 'origin' }, 'worktreeStart', 'invalid_value'],
])('editChatSettings refuses %o with the key path and kind, and leaves the file as it was', async (changes, path, problem) => {
  const text = '{ "agents": {},\n  "archiveAfterDays": 20 }\n';
  seed(text);
  const reply = await edit(changes);
  expect(reply).toMatchObject({ id: 1, ok: false, code: 'config.problem', params: { path, problem } });
  expect(reply.error).toContain(path);
  expect(readFileSync(settingsFile(), 'utf8')).toBe(text);
});

test.each([['[1, 2]', 'notAnObject'], ['"text"', 'notAnObject'], ['{ not json', 'notJson']])('editChatSettings refuses a chat.json that holds %s and leaves it as it was', async (text, problem) => {
  seed(text);
  expect(await edit({ archiveAfterDays: 7 })).toMatchObject({ ok: false, code: 'config.problem', params: { path: '(file)', problem } });
  expect(readFileSync(settingsFile(), 'utf8')).toBe(text);
});

test('editChatSettings takes only the four settings, and its request and reply are the golden files', async () => {
  await open();
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"editChatSettings","changes":{"projectsFolder":"/x"}}')).toMatchObject({ ok: false, code: 'request.invalid' });
  expect(await c.ask('{"id":2,"cmd":"editChatSettings"}')).toMatchObject({ ok: false, code: 'request.invalid' });
  // what the app sends and the host answers (macos/Tests/CarrierCoreTests/Connection/ChatHostTests.swift); UPDATE_FIXTURES=1 rewrites it
  const request = { cmd: 'editChatSettings', changes: { archiveAfterDays: 7, deleteAfterDays: 'never', worktreeStart: 'local', idleCloseMinutes: null } };
  const { id, ...reply } = await c.ask(JSON.stringify({ id: 3, ...request }));
  const json = `${JSON.stringify({ request, reply }, null, 2)}\n`;
  const file = fileURLToPath(new URL('../../macos/Tests/Fixtures/chat-edit-settings.json', import.meta.url));
  if (process.env.UPDATE_FIXTURES === '1') writeFileSync(file, json);
  expect(json).toBe(readFileSync(file, 'utf8'));
  expect(id).toBe(3);
});

// The nine requests that change projects.json and projectsFolder: the writing code is tested in project-edits.test.ts; here the wire (what a client may send) and the golden file.
const projectsFile = () => projectsPathOf(home());
const seedProjects = (projects: unknown[]) => (mkdirSync(home(), { recursive: true }), writeFileSync(projectsFile(), `${JSON.stringify({ projects }, null, 2)}\n`));
const ask = async (request: object) => {
  await open();
  return (await client()).ask(JSON.stringify({ id: 1, ...request }));
};

test.each([
  [{ cmd: 'addProject' }],
  [{ cmd: 'addProject', folder: '' }],
  [{ cmd: 'addProject', folder: '/w/a', extra: 1 }],
  [{ cmd: 'removeProject', path: 3 }],
  [{ cmd: 'editProject', path: '/w/a', key: 'origin', value: 'cloned' }],
  [{ cmd: 'editProject', path: '/w/a', key: 'name', value: 3 }],
  [{ cmd: 'moveProject', path: '/w/a' }],
  [{ cmd: 'editProjectIcon', path: '/w/a', changes: { size: 3 } }],
  [{ cmd: 'editProjectDefaults', path: '/w/a', changes: { access: 'plan' } }],
  [{ cmd: 'editProjectTags', path: '/w/a', add: 'x', remove: [] }],
  [{ cmd: 'setProjectActions', path: '/w/a', actions: [{ name: 'a', command: 'b', when: 'afterClone', timeout: 3 }] }],
  [{ cmd: 'setProjectsFolder', folder: 4 }],
])('%o is refused as an invalid request', async (request) => {
  seedProjects([{ path: '/w/a', origin: 'added' }]);
  expect(await ask(request)).toMatchObject({ ok: false, code: 'request.invalid' });
});

test('a refused change of a project answers its code and the key path and kind, and leaves the file as it was', async () => {
  const text = `${JSON.stringify({ projects: [{ path: '/w/a', origin: 'added' }] }, null, 2)}\n`;
  seedProjects([{ path: '/w/a', origin: 'added' }]);
  expect(await ask({ cmd: 'editProject', path: '/w/a', key: 'name', value: true })).toMatchObject({ ok: false, code: 'config.problem', params: { path: 'projects.0.name', problem: 'invalid_type' } });
  expect(await ask({ cmd: 'editProject', path: '/w/none', key: 'name', value: 'x' })).toMatchObject({ ok: false, code: 'project.missing', params: { path: '/w/none' } });
  expect(readFileSync(projectsFile(), 'utf8')).toBe(text);
});

test('the nine project requests and their replies are the golden file', async () => {
  const alpha = { path: '/Users/example/work/alpha', name: 'alpha', origin: 'cloned', tags: ['a', 'b'], icon: { color: 'blue', image: 'alpha.png' }, defaults: { agent: 'claude', model: 'opus' } };
  seedProjects([alpha, { path: '/Users/example/work/beta', origin: 'added' }]);
  mkdirSync(home(), { recursive: true });
  writeFileSync(settingsFile(), '{ "archiveAfterDays": 20 }');
  const steps: [string, object][] = [
    ['addProject', { cmd: 'addProject', folder: '/Users/example/work/gamma' }],
    ['addProjectExisting', { cmd: 'addProject', folder: '/Users/example/work/gamma/' }],
    ['removeProject', { cmd: 'removeProject', path: '/Users/example/work/beta' }],
    ['editProject', { cmd: 'editProject', path: alpha.path, key: 'name', value: 'Alpha' }],
    ['moveProject', { cmd: 'moveProject', path: alpha.path, folder: '/Users/example/work/alpha-2' }],
    ['editProjectIcon', { cmd: 'editProjectIcon', path: '/Users/example/work/alpha-2', changes: { color: null, mark: 'bolt' } }],
    ['editProjectDefaults', { cmd: 'editProjectDefaults', path: '/Users/example/work/alpha-2', changes: { model: null, workIn: 'worktree' } }],
    ['editProjectTags', { cmd: 'editProjectTags', path: '/Users/example/work/alpha-2', add: ['C', ' d '], remove: ['a'] }],
    ['setProjectActions', { cmd: 'setProjectActions', path: '/Users/example/work/alpha-2', actions: [{ name: 'Install', command: 'pnpm i', when: 'newWorktree', onFail: 'stop' }] }],
    ['setProjectsFolder', { cmd: 'setProjectsFolder', folder: '/Users/example/projects' }],
    ['missing', { cmd: 'removeProject', path: '/Users/example/work/none' }],
    ['refused', { cmd: 'editProject', path: '/Users/example/work/gamma', key: 'name', value: true }],
  ];
  await open();
  const c = await client();
  const golden: Record<string, unknown> = {};
  for (const [name, request] of steps) {
    const { id, ...reply } = await c.ask(JSON.stringify({ id: 1, ...request }));
    golden[name] = { request, reply };
  }
  // what the app sends and the host answers (macos/Tests/CarrierCoreTests/Connection/ChatHostTests.swift); UPDATE_FIXTURES=1 rewrites it
  const json = `${JSON.stringify(golden, null, 2)}\n`;
  const path = fileURLToPath(new URL('../../macos/Tests/Fixtures/chat-edit-projects.json', import.meta.url));
  if (process.env.UPDATE_FIXTURES === '1') writeFileSync(path, json);
  expect(json).toBe(readFileSync(path, 'utf8'));
  expect(JSON.parse(readFileSync(chatConfigPathOf(home()), 'utf8'))).toEqual({ archiveAfterDays: 20, projectsFolder: '/Users/example/projects' });
});
