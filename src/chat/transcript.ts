import { boundOutput, clean } from '../execution/events.ts';
import type { StepEvent } from './plan.ts';
import type { ChatEvent } from './runner.ts';

// Characters, not bytes. The limits of a conversation, not of an epic's log (spec: The record).
export const chatCaps = { message: 64_000, arg: 1024, title: 80, preview: 200, error: 4096 };

/** What is stored of an event: redacted first and then cut, so a secret is never cut in a way that hides its shape. A `delta` is not stored. */
export function boundEvent(event: ChatEvent | StepEvent): Record<string, unknown> | undefined {
  switch (event.kind) {
    case 'delta':
      return undefined;
    case 'user':
      return { text: clean(event.text, chatCaps.message), ...(event.command !== undefined && { command: event.command }) };
    case 'assistant':
    case 'reasoning':
      return { text: clean(event.text, chatCaps.message) };
    case 'error':
      return { text: clean(event.text, chatCaps.error) };
    case 'tool_start':
    case 'tool_end': {
      const { kind: _kind, arg, output, ...rest } = event;
      return { ...rest, ...(arg !== undefined && { arg: clean(arg, chatCaps.arg) }), ...(output !== undefined && { output: boundOutput(output.join('\n')) }) };
    }
    case 'approval': {
      const { kind: _kind, arg, questions, ...rest } = event;
      // ponytail: an answer is matched to its question by the stored text, so a question the redaction changed is answered under the changed text
      const bound = questions?.map((q) => ({
        question: clean(q.question, chatCaps.arg),
        header: clean(q.header, chatCaps.arg),
        multiSelect: q.multiSelect,
        options: q.options.map((o) => ({ label: clean(o.label, chatCaps.arg), description: clean(o.description, chatCaps.arg), ...(o.preview !== undefined && { preview: clean(o.preview, chatCaps.message) }) })),
      }));
      return { ...rest, ...(arg !== undefined && { arg: clean(arg, chatCaps.arg) }), ...(bound !== undefined && { questions: bound }) };
    }
    case 'approval_answered': {
      const { kind: _kind, answers, ...rest } = event;
      return { ...rest, ...(answers !== undefined && { answers: Object.fromEntries(Object.entries(answers).map(([q, a]) => [clean(q, chatCaps.arg), clean(a, chatCaps.message)])) }) };
    }
    default: {
      const { kind: _kind, ...rest } = event;
      return rest;
    }
  }
}

/** What a list says of a session's last message: its words on one line, cut. */
export const previewOf = (text: string) => clean(text.replace(/\s+/g, ' ').trim(), chatCaps.preview);

/** The title of a session: the first line of its first message, cut. */
export const titleOf = (text: string) => clean(text.trim().split('\n')[0]!, chatCaps.title);
