import type { Readable } from 'node:stream';
import type { z } from 'zod';
import { chatPlacesOf, engineConfigPathOf, enginePlacesOf } from '../../../config/places.ts';
import { editChatSettings } from '../../../chat/config.ts';
import { ChatRefused } from '../../../chat/runner.ts';
import { projectEdits } from '../../../chat/project-edits.ts';
import { providersRequests } from '../../../chat/providers-requests.ts';
import { addAccountRequest, editAccountRequest, editChatSettingsRequest, projectRequests, removeAccountRequest, setAccountsRequest, setTextGeneratorRequest } from '../../../chat/server.ts';
import { ConfigRefused } from '../../../config/engine-edit.ts';
import { withEngine, writeEngineConfig } from '../../../control/config.ts';
import { editBehaviorRequest, refused, setWatchedReposRequest } from '../../../control/server.ts';
import { connectControl, ControlRefused, ControlUnreachable } from '../control-client.ts';

/** The reply the socket would give, minus its `id`. */
type Printed = { ok: true; data: unknown } | { ok: false; error: string; code?: string; params?: Record<string, string | number> };

const chatSocket = (folder: string) => chatPlacesOf(folder).socket;
const engineSocket = (folder: string) => enginePlacesOf(folder).socket;

/** The requests of the `config` capability this command runs: the socket's schema (with its `id`), the socket of the process that owns the file and the code that owner runs for it, which this process runs when no owner answers. */
const requests: Record<string, { schema: z.ZodType; socket: (folder: string) => string; run: (request: any, folder: string) => unknown }> = {
  editChatSettings: { schema: editChatSettingsRequest, socket: chatSocket, run: (request, folder) => editChatSettings(request.changes, folder) },
  setAccounts: { schema: setAccountsRequest, socket: chatSocket, run: (request, folder) => providersRequests(folder).setAccounts(request) },
  addAccount: { schema: addAccountRequest, socket: chatSocket, run: (request, folder) => providersRequests(folder).addAccount(request) },
  editAccount: { schema: editAccountRequest, socket: chatSocket, run: (request, folder) => providersRequests(folder).editAccount(request) },
  removeAccount: { schema: removeAccountRequest, socket: chatSocket, run: (request, folder) => providersRequests(folder).removeAccount(request) },
  setTextGenerator: { schema: setTextGeneratorRequest, socket: chatSocket, run: (request, folder) => providersRequests(folder).setTextGenerator(request) },
  // nobody answers for `engine.json`, so nobody runs on what is written
  setWatchedRepos: { schema: setWatchedReposRequest, socket: engineSocket, run: (request, folder) => withEngine(writeEngineConfig(request, engineConfigPathOf(folder), folder)) },
  editBehavior: { schema: editBehaviorRequest, socket: engineSocket, run: (request, folder) => withEngine(writeEngineConfig(request, engineConfigPathOf(folder), folder)) },
};
// the nine requests that write projects.json and projectsFolder: the owner's code takes the fields, not the socket's `id` and `cmd`
for (const schema of projectRequests) {
  const cmd = schema.shape.cmd.value;
  requests[cmd] = { schema, socket: chatSocket, run: ({ id, cmd: _, ...fields }, folder) => (projectEdits as Record<string, (fields: never, folder: string) => unknown>)[cmd]!(fields as never, folder) };
}

/** The reply of the process that owns the file when it answers on `socket` and lists `config` (the chat host for `chat.json`, `providers.json` and `projects.json`, the engine for `engine.json`); null when none does, so the caller writes the file itself. */
async function askOwner(socket: string, cmd: string, fields: Record<string, unknown>): Promise<Printed | null> {
  try {
    const client = await connectControl(socket);
    try {
      if (client.hello.capabilities.includes('config') === false) return null; // an older process: it reads the file again when it needs it, so a write by this process is as good
      return { ok: true, data: await client.request(cmd, fields) };
    } finally {
      client.close();
    }
  } catch (error) {
    if (error instanceof ControlRefused) return { ok: false, error: error.message, ...(error.code !== undefined && { code: error.code }), params: error.params };
    if (error instanceof ControlUnreachable) return null;
    throw error;
  }
}

/**
 * `carrier config`: one config request on standard input as one line of JSON (the request of the socket, without its `id`), forwarded to the process that owns the file when it answers
 * and otherwise written here by the same code. Prints the reply the socket would give, minus its `id`, as one line of JSON ([ADR 0053](../../../../docs/adr/0053-a-carrier-config-file-has-one-owner-process-and-a-front-end-writes-it-through-that-process.md)).
 * Returns 0 when it saved, 1 when it refused, 2 when standard input is not a request it can run.
 */
export async function configCommand(folder: string, input: Readable = process.stdin): Promise<number> {
  const print = (reply: Printed) => void process.stdout.write(`${JSON.stringify(reply)}\n`);
  let text = '';
  for await (const chunk of input) text += chunk;
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    const { id, ...reply } = refused(null, 'request.invalidJson', 'invalid JSON');
    return print(reply as Printed), 2;
  }
  // `id` belongs to the socket: a request of this command has none
  const asked = (typeof value === 'object' && value !== null ? value : {}) as Record<string, unknown>;
  const handler = 'id' in asked === false && typeof asked.cmd === 'string' && Object.hasOwn(requests, asked.cmd) ? requests[asked.cmd] : undefined;
  const request = handler?.schema.safeParse({ ...asked, id: 1 });
  if (handler === undefined || request?.success !== true) {
    const { id, ...reply } = refused(null, 'request.invalid', 'invalid request');
    return print(reply as Printed), 2;
  }
  const { id, cmd, ...fields } = request.data as { id: number; cmd: string };
  let reply = await askOwner(handler.socket(folder), cmd, fields);
  if (reply === null) {
    try {
      reply = { ok: true, data: await handler.run(request.data, folder) };
    } catch (error) {
      if (error instanceof ChatRefused === false && error instanceof ConfigRefused === false) throw error;
      reply = { ok: false, error: error.message, code: error.code, params: error.params };
    }
  }
  print(reply);
  return reply.ok ? 0 : 1;
}
