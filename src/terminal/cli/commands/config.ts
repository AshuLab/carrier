import type { Readable } from 'node:stream';
import { z } from 'zod';
import { chatPlacesOf, engineConfigPathOf, enginePlacesOf } from '../../../config/places.ts';
import { editChatSettings } from '../../../chat/config.ts';
import { ChatRefused } from '../../../chat/runner.ts';
import { editChatSettingsRequest } from '../../../chat/server.ts';
import { ConfigRefused } from '../../../config/engine-edit.ts';
import { withEngine, writeEngineConfig } from '../../../control/config.ts';
import { editBehaviorRequest, refused, setWatchedReposRequest } from '../../../control/server.ts';
import { connectControl, ControlRefused, ControlUnreachable } from '../control-client.ts';

/** The reply the socket would give, minus its `id`. */
type Printed = { ok: true; data: unknown } | { ok: false; error: string; code?: string; params?: Record<string, string | number> };

/** The requests `carrier config` takes: the socket's, without their `id`. */
const configRequest = z.union([editChatSettingsRequest.omit({ id: true }), setWatchedReposRequest.omit({ id: true }), editBehaviorRequest.omit({ id: true })]);

/** The reply of the process that owns the file when it answers on `socket` and lists `config` (the chat host for `chat.json`, the engine for `engine.json`); null when none does, so the caller writes the file itself. */
async function askOwner(socket: string, { cmd, ...fields }: z.infer<typeof configRequest>): Promise<Printed | null> {
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
  const request = configRequest.safeParse(value);
  if (request.success === false) {
    const { id, ...reply } = refused(null, 'request.invalid', 'invalid request');
    return print(reply as Printed), 2;
  }
  const socket = request.data.cmd === 'editChatSettings' ? chatPlacesOf(folder).socket : enginePlacesOf(folder).socket;
  let reply = await askOwner(socket, request.data);
  if (reply === null) {
    try {
      // nobody answers for `engine.json`, so nobody runs on what is written
      reply = { ok: true, data: request.data.cmd === 'editChatSettings' ? editChatSettings(request.data.changes, folder) : withEngine(writeEngineConfig(request.data, engineConfigPathOf(folder), folder)) };
    } catch (error) {
      if (error instanceof ChatRefused === false && error instanceof ConfigRefused === false) throw error;
      reply = { ok: false, error: error.message, code: error.code, params: error.params };
    }
  }
  print(reply);
  return reply.ok ? 0 : 1;
}
