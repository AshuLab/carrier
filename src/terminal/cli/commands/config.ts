import type { Readable } from 'node:stream';
import type { z } from 'zod';
import { chatPlacesOf } from '../../../config/places.ts';
import { editChatSettings } from '../../../chat/config.ts';
import { ChatRefused } from '../../../chat/runner.ts';
import { projectEdits } from '../../../chat/project-edits.ts';
import { providersRequests } from '../../../chat/providers-requests.ts';
import { addAccountRequest, editAccountRequest, editChatSettingsRequest, projectRequests, removeAccountRequest, setAccountsRequest, setTextGeneratorRequest } from '../../../chat/server.ts';
import { refused } from '../../../control/server.ts';
import { connectControl, ControlRefused, ControlUnreachable } from '../control-client.ts';

/** The reply the socket would give, minus its `id`. */
type Printed = { ok: true; data: unknown } | { ok: false; error: string; code?: string; params?: Record<string, string | number> };

/** The requests of the `config` capability this command runs: the socket's schema (with its `id`) and the code the owner runs for it, which this process runs when no owner answers. */
const requests: Record<string, { schema: z.ZodType; run: (request: any, folder: string) => unknown }> = {
  editChatSettings: { schema: editChatSettingsRequest, run: (request, folder) => editChatSettings(request.changes, folder) },
  setAccounts: { schema: setAccountsRequest, run: (request, folder) => providersRequests(folder).setAccounts(request) },
  addAccount: { schema: addAccountRequest, run: (request, folder) => providersRequests(folder).addAccount(request) },
  editAccount: { schema: editAccountRequest, run: (request, folder) => providersRequests(folder).editAccount(request) },
  removeAccount: { schema: removeAccountRequest, run: (request, folder) => providersRequests(folder).removeAccount(request) },
  setTextGenerator: { schema: setTextGeneratorRequest, run: (request, folder) => providersRequests(folder).setTextGenerator(request) },
};
// the nine requests that write projects.json and projectsFolder: the owner's code takes the fields, not the socket's `id` and `cmd`
for (const schema of projectRequests) {
  const cmd = schema.shape.cmd.value;
  requests[cmd] = { schema, run: ({ id, cmd: _, ...fields }, folder) => (projectEdits as Record<string, (fields: never, folder: string) => unknown>)[cmd]!(fields as never, folder) };
}

/** The reply of the host that answers on `chat.sock` and lists `config`; null when none does, so the caller writes the file itself. */
async function askOwner(folder: string, cmd: string, fields: Record<string, unknown>): Promise<Printed | null> {
  try {
    const client = await connectControl(chatPlacesOf(folder).socket);
    try {
      if (client.hello.capabilities.includes('config') === false) return null; // an older host: its settings are read each pass, so a write by this process is as good
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
  let reply = await askOwner(folder, cmd, fields);
  if (reply === null) {
    try {
      reply = { ok: true, data: await handler.run(request.data, folder) };
    } catch (error) {
      if (error instanceof ChatRefused === false) throw error;
      reply = { ok: false, error: error.message, code: error.code, params: error.params };
    }
  }
  print(reply);
  return reply.ok ? 0 : 1;
}
