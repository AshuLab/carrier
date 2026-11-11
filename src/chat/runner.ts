import type { Account } from '../config/providers.ts';

// The chat runner: the port through which the host drives one provider (docs/specs/chat-host.md, Decisions). It speaks
// Carrier's own chat events whatever the provider speaks, and it is not the engine's `AgentRunner`: nothing in it is
// epic-shaped, there is no result file and the process is not done after one answer.

/** A value of an option: `detail` says what it is in a line, `version` which exact thing it stands for (a model's alias is not its number). */
export type ChatOptionValue = { id: string; label: string; detail?: string; version?: string };
export type ChatOption = { id: string; label: string; values: ChatOptionValue[]; current: string };
/**
 * Something the person can invoke from the message box, whatever the provider calls it (Claude's slash commands and skills, Codex's
 * skills). The host and the clients speak of this and never of a provider's own way: each adapter lists its own as `ChatCommand`s and
 * turns an invocation into what its provider takes.
 */
export type ChatCommand = {
  /** The provider's own identity for it, opaque to a client: what `send` names it by. */
  id: string;
  /** What the person types after the slash. */
  name: string;
  description: string;
  /** What it takes after its name, when the provider says (`<file>`). */
  argumentHint?: string;
  /** A skill is the person's or a plugin's; a command is the provider's own (`/compact`). */
  kind: 'skill' | 'command';
};
export type ChatChoice = { id: string; label: string; allow: boolean };
/** A question the agent asks the person with options to pick from; the person may also write an answer of their own. */
export type ChatQuestion = { question: string; header: string; options: { label: string; description: string; preview?: string }[]; multiSelect: boolean };
/** As the provider reports it. */
export type ChatUsage = Record<string, number>;

export type ChatEvent =
  | { kind: 'user'; text: string; /** The name of the command invoked, when the message invoked one. */ command?: string }
  | { kind: 'assistant'; text: string } // a finished message
  | { kind: 'reasoning'; text: string } // one finished thinking block, before the answer of its turn; never streamed
  | { kind: 'delta'; text: string } // streaming, never stored
  | { kind: 'tool_start' | 'tool_end'; callId: string; tool: string; arg?: string; output?: string[]; status?: 'ok' | 'err' }
  | { kind: 'approval'; approvalId: string; tool: string; arg?: string; choices: ChatChoice[]; /** Set when the approval is the agent asking questions: the person answers them with `answers`. */ questions?: ChatQuestion[] }
  | { kind: 'approval_answered'; approvalId: string; choiceId: string; /** Question text to the answer; a multiple choice joins its picks with a comma. */ answers?: Record<string, string> }
  | { kind: 'option'; id: string; value: string }
  | { kind: 'turn_end'; outcome: 'ok' | 'interrupted' | 'error'; model?: string; usage?: ChatUsage }
  | { kind: 'error'; text: string };

export interface ChatConversation {
  readonly options: ChatOption[];
  /** What the provider lets the person invoke in this conversation; empty when it has none or does not say. */
  readonly commands: ChatCommand[];
  /** The provider's id for this conversation, once it has one. */
  readonly nativeId: string | undefined;
  /** The agent's process, when it leads a group of its own: what the next host needs to sweep it if this one dies. `command` is what it was started with. */
  readonly process?: { pid: number; pgid: number; command: string };
  /** `text` is the message, or what follows the command's name when one is invoked (the provider's own way of invoking it is the adapter's). */
  send(text: string, command?: ChatCommand): void;
  answer(approvalId: string, choiceId: string, answers?: Record<string, string>): void;
  interrupt(): Promise<void>;
  setOption(id: string, value: string): Promise<void>;
  close(): Promise<void>;
  onEvent(listener: (event: ChatEvent) => void): void;
  /** Called once when the agent's process ends on its own, after the events that say so; never for a `close()`. */
  onEnd(listener: () => void): void;
}

/** What an account sets of how its CLI starts, besides its binary and login (`providers.json`): the adapter turns it into the arguments its CLI takes. */
export type ChatLaunch = Pick<Account, 'autoCompact' | 'idleCompaction' | 'launchArgs'>;

export interface ChatRunner {
  /** Rejects with a `ChatRefused` when the provider is not installed, not logged in, or does not know the id to resume. */
  open(args: { folder: string; resume?: string; options?: Record<string, string>; /** The agent's `command` from the config: the binary to run, else the one on the path. */ command?: string; /** The account's compaction and launch arguments; none when it sets none. */ launch?: ChatLaunch; env: NodeJS.ProcessEnv }): Promise<ChatConversation>;
}

/** A failure whose message is for the person, in words: it travels to the client as it is. Any other error is logged and reaches the client as "internal error". */
export class ChatRefused extends Error {}
