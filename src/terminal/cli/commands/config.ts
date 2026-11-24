import type { Readable } from 'node:stream';
import { chatPlacesOf } from '../../../config/places.ts';
import { editChatSettings } from '../../../chat/config.ts';
import { ChatRefused } from '../../../chat/runner.ts';
import { projectEdits } from '../../../chat/project-edits.ts';
import { chatRequest, projectRequests } from '../../../chat/server.ts';
import { refused } from '../../../control/server.ts';
import { connectControl, ControlRefused, ControlUnreachable } from '../control-client.ts';

/** The reply the socket would give, minus its `id`. */
type Printed = { ok: true; data: unknown } | { ok: false; error: string; code?: string; params?: Record<string, string | number> };

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
  // the requests of the `config` capability, by name: the socket's schema checks them (without an `id` of their own) and the same code answers them
  const names = new Set<unknown>(['editChatSettings', ...projectRequests.map((request) => request.shape.cmd.value)]);
  const named = typeof value === 'object' && value !== null && 'id' in value === false && names.has((value as { cmd?: unknown }).cmd);
  const request = named ? chatRequest.safeParse({ id: 1, ...(value as object) }) : undefined;
  if (request?.success !== true) {
    const { id, ...reply } = refused(null, 'request.invalid', 'invalid request');
    return print(reply as Printed), 2;
  }
  const { id, cmd, ...fields } = request.data;
  let reply = await askOwner(folder, cmd, fields);
  if (reply === null) {
    try {
      const write = cmd === 'editChatSettings' ? () => editChatSettings((fields as { changes: object }).changes, folder) : () => (projectEdits as Record<string, (fields: never, folder: string) => unknown>)[cmd]!(fields as never, folder);
      reply = { ok: true, data: write() };
    } catch (error) {
      if (error instanceof ChatRefused === false) throw error;
      reply = { ok: false, error: error.message, code: error.code, params: error.params };
    }
  }
  print(reply);
  return reply.ok ? 0 : 1;
}
