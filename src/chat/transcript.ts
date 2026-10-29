import { boundOutput, clean } from '../execution/events.ts';
import type { ChatEvent } from './runner.ts';

// Characters, not bytes. The limits of a conversation, not of an epic's log (spec: The record).
export const chatCaps = { message: 64_000, arg: 1024, title: 80, error: 4096 };

/** What is stored of an event: redacted first and then cut, so a secret is never cut in a way that hides its shape. A `delta` is not stored. */
export function boundEvent(event: ChatEvent): Record<string, unknown> | undefined {
  switch (event.kind) {
    case 'delta':
      return undefined;
    case 'user':
      return { text: clean(event.text, chatCaps.message), ...(event.command !== undefined && { command: event.command }) };
    case 'assistant':
      return { text: clean(event.text, chatCaps.message) };
    case 'error':
      return { text: clean(event.text, chatCaps.error) };
    case 'tool_start':
    case 'tool_end': {
      const { kind: _kind, arg, output, ...rest } = event;
      return { ...rest, ...(arg !== undefined && { arg: clean(arg, chatCaps.arg) }), ...(output !== undefined && { output: boundOutput(output.join('\n')) }) };
    }
    case 'approval': {
      const { kind: _kind, arg, ...rest } = event;
      return { ...rest, ...(arg !== undefined && { arg: clean(arg, chatCaps.arg) }) };
    }
    default: {
      const { kind: _kind, ...rest } = event;
      return rest;
    }
  }
}

/** The title of a session: the first line of its first message, cut. */
export const titleOf = (text: string) => clean(text.trim().split('\n')[0]!, chatCaps.title);
