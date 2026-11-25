import { z } from 'zod';
import { defineTool, type StoredEvent } from '../mcp.ts';
import { ChatRefused } from '../runner.ts';

const LIST_TEXT = 1500;
const PART = 4000;
// What each view lists. Reasoning is in neither, and a tool call is its start (its end only says how it went).
const kinds = { messages: ['user', 'assistant'], activity: ['user', 'assistant', 'tool_start'] };

const noSession = () => new ChatRefused('history.noSession', 'There is no such session');
const noItem = () => new ChatRefused('history.noItem', 'There is no such item');

/** What an event says in the history: a message as it was said (a command the person invoked is stored as the command), a tool call as one line with no output. */
const textOf = (event: StoredEvent, status: Record<string, 'ok' | 'err'>) =>
  event.kind === 'tool_start' ? `${String(event.data.tool)}${typeof event.data.arg === 'string' && event.data.arg !== '' ? ` ${event.data.arg}` : ''} (${status[String(event.data.callId)] ?? 'running'})` : String(event.data.text ?? '');

/** The stored events of the calling session, so an agent that took over from another can read what came before; a parent also reads its children and a child its parent, and nothing else. */
export const history = defineTool({
  name: 'history',
  description:
    "Reads the stored events of this session, or of one of its children or its parent when sessionId names it, oldest first. view 'messages' (default) lists what the person and the assistant said; 'activity' also lists each tool call as one line, with no output. Reasoning is never returned. " +
    `A list holds at most limit events (1 to 100, default 40) after afterPosition (-1, the default, starts at the beginning); each event has a position, its id, and its text cut to ${LIST_TEXT} characters. ` +
    `Call again with afterPosition set to nextPosition until it is null. To read one event whole, pass its id as itemId: it answers ${PART} characters at a time with nextTextOffset, which you pass back as textOffset until it is null.`,
  access: 'readsAsSession',
  // no defaults in the schema: a client would read a defaulted key as required
  input: z
    .strictObject({
      sessionId: z.string().optional(),
      view: z.enum(['messages', 'activity']).optional(),
      afterPosition: z.int().min(-1).optional(),
      limit: z.int().min(1).max(100).optional(),
      itemId: z.string().optional(),
      textOffset: z.int().min(0).optional(),
    })
    .refine((args) => args.textOffset === undefined || args.itemId !== undefined, { message: 'textOffset needs an itemId' }),
  handler: ({ sessionId: asked, view = 'messages', afterPosition = -1, limit = 40, itemId, textOffset = 0 }, ctx) => {
    const { sessions } = ctx;
    if (asked !== undefined && asked !== ctx.sessionId && !sessions.related(ctx.sessionId, asked)) throw noSession(); // the same words as a session that does not exist
    const sessionId = asked ?? ctx.sessionId;

    if (itemId !== undefined) {
      const position = /^(0|[1-9]\d*)$/.test(itemId) ? Number(itemId) : NaN;
      const event = Number.isSafeInteger(position) ? sessions.storedEvent(sessionId, position, kinds.activity) : undefined;
      if (event === undefined) throw noItem();
      const text = textOf(event, sessions.toolStatuses(sessionId, event.kind === 'tool_start' ? [String(event.data.callId)] : []));
      const next = textOffset + PART;
      return { itemId, text: text.slice(textOffset, next), nextTextOffset: next < text.length ? next : null };
    }

    // one more than asked, to know whether the end was reached
    const found = sessions.storedEvents(sessionId, { after: afterPosition, kinds: kinds[view], limit: limit + 1 });
    const page = found.slice(0, limit);
    const status = sessions.toolStatuses(sessionId, page.filter((event) => event.kind === 'tool_start').map((event) => String(event.data.callId)));
    return {
      events: page.map((event) => ({ position: event.position, id: String(event.position), kind: event.kind === 'tool_start' ? 'tool' : event.kind, text: textOf(event, status).slice(0, LIST_TEXT) })),
      nextPosition: found.length > limit ? page.at(-1)!.position : null,
    };
  },
});
