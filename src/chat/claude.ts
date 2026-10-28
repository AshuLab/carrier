import { execFile, spawn } from 'node:child_process';
import { query as sdkQuery, type ModelInfo, type PermissionResult, type PermissionUpdate, type Query, type SDKMessage, type SDKUserMessage } from '@anthropic-ai/claude-agent-sdk';
import { createScopedLogger } from '@ashulab/universal-logger';
import { endGroup, resolveAgentBinary } from './group.ts';
import { ChatRefused, type ChatChoice, type ChatConversation, type ChatEvent, type ChatOption, type ChatRunner, type ChatUsage } from './runner.ts';

// The Claude adapter of the chat runner: the Agent SDK pointed at the user's own `claude` binary, which runs as the
// leader of its own process group (docs/research/chat-spike.md). The SDK is only the transport: everything below the
// `query` seam is Carrier's own parsing of the messages it yields, and a message it does not know gives no event.

const log = createScopedLogger('chat');

const PERMISSION_MODES = [
  { id: 'default', label: 'Ask before each change' },
  { id: 'acceptEdits', label: 'Accept edits' },
  { id: 'plan', label: 'Plan only' },
  { id: 'auto', label: 'Auto' },
  { id: 'dontAsk', label: "Don't ask" },
]; // `bypassPermissions` is left out: it needs a flag of its own and Carrier does not turn it on

export type ClaudeChatDeps = {
  query: typeof sdkQuery;
  /** The `claude` to run: `command` when given, else the one found on the path. Throws when there is none. */
  resolve: (command: string | undefined, env: NodeJS.ProcessEnv) => string;
  /** Whether the user is logged in to the binary. */
  loggedIn: (binary: string, env: NodeJS.ProcessEnv) => Promise<boolean>;
  /** Starts the binary as the leader of its own group. Absent in tests, where the transport is the query itself. */
  spawn?: NonNullable<Parameters<typeof sdkQuery>[0]['options']>['spawnClaudeCodeProcess'];
};

const resolveClaude = (command: string | undefined, env: NodeJS.ProcessEnv) => resolveAgentBinary('claude', command, env);

const claudeLoggedIn = (binary: string, env: NodeJS.ProcessEnv) =>
  new Promise<boolean>((done) => {
    execFile(binary, ['auth', 'status'], { env, timeout: 15_000 }, (_error, stdout) => {
      try {
        done((JSON.parse(stdout) as { loggedIn?: unknown }).loggedIn === true);
      } catch {
        done(false);
      }
    });
  });

const ownGroup: NonNullable<ClaudeChatDeps['spawn']> = (o) => spawn(o.command, o.args, { cwd: o.cwd, env: o.env as NodeJS.ProcessEnv, stdio: ['pipe', 'pipe', 'pipe'], detached: true });

export const realClaudeDeps: ClaudeChatDeps = { query: sdkQuery, resolve: resolveClaude, loggedIn: claudeLoggedIn, spawn: ownGroup };

export function claudeChatRunner(deps: ClaudeChatDeps = realClaudeDeps): ChatRunner {
  return {
    async open({ folder, resume, options = {}, command, env }) {
      let binary: string;
      try {
        binary = deps.resolve(command, env);
      } catch {
        throw new ChatRefused(`Claude is not installed: ${command === undefined ? 'there is no "claude" on the path' : `"${command}" cannot be run`}`);
      }
      if (!(await deps.loggedIn(binary, env))) throw new ChatRefused('Claude is not logged in; run "claude" once to log in');
      const conversation = new ClaudeConversation(options, resume);
      try {
        await conversation.start(deps, { folder, binary, env });
      } catch (error) {
        log.error('claude could not be started', error);
        await conversation.close();
        throw new ChatRefused(resume === undefined ? 'Claude could not be started' : 'Claude could not resume that conversation');
      }
      return conversation;
    },
  };
}

class ClaudeConversation implements ChatConversation {
  nativeId: string | undefined;
  private listeners: ((event: ChatEvent) => void)[] = [];
  private query!: Query;
  private models: ModelInfo[] = [];
  private mode: string;
  private model: string;
  private effort: string;
  private input = inputQueue();
  private pending = new Map<string, { input: Record<string, unknown>; suggestions: PermissionUpdate[]; resolve: (result: PermissionResult) => void }>();
  private tools = new Map<string, string>();
  private turning = false;
  private interrupting = false;
  /** Turns that Carrier started itself (an `/effort` change) and the person must not see. */
  private hidden = 0;
  private lastModel: string | undefined;
  private closing = false;
  private pid: number | undefined;
  private command: string | undefined;
  private chosen: Record<string, string>;

  constructor(chosen: Record<string, string>, resume: string | undefined) {
    this.chosen = chosen;
    this.nativeId = resume;
    this.mode = chosen.permissionMode ?? 'default';
    this.model = chosen.model ?? 'default';
    this.effort = chosen.effort ?? '';
  }

  async start(deps: ClaudeChatDeps, { folder, binary, env }: { folder: string; binary: string; env: NodeJS.ProcessEnv }) {
    const spawnOwn = deps.spawn && ((o: Parameters<NonNullable<ClaudeChatDeps['spawn']>>[0]) => {
      const child = deps.spawn!(o);
      this.pid = (child as { pid?: number }).pid;
      this.command = o.command;
      return child;
    });
    this.query = deps.query({
      prompt: this.input.iterable,
      options: {
        cwd: folder,
        env,
        pathToClaudeCodeExecutable: binary,
        includePartialMessages: true,
        canUseTool: (tool, input, { toolUseID, suggestions = [], title }) => this.ask(toolUseID, tool, input, suggestions, title),
        ...(spawnOwn && { spawnClaudeCodeProcess: spawnOwn }),
        ...(this.chosen.model && { model: this.chosen.model }),
        ...(this.chosen.permissionMode && { permissionMode: this.chosen.permissionMode as never }),
        ...(this.chosen.effort && { effort: this.chosen.effort as never }),
        ...(this.nativeId && { resume: this.nativeId }),
      },
    });
    this.models = (await this.query.initializationResult()).models;
    void this.pump();
  }

  get process() {
    return this.pid === undefined || this.command === undefined ? undefined : { pid: this.pid, pgid: this.pid, command: this.command }; // it leads its own group (`ownGroup`)
  }

  get options(): ChatOption[] {
    const efforts = this.models.find((m) => m.value === this.model)?.supportedEffortLevels ?? this.models.find((m) => m.value === 'default')?.supportedEffortLevels ?? [];
    return [
      { id: 'permissionMode', label: 'Permission mode', values: PERMISSION_MODES, current: this.mode },
      { id: 'model', label: 'Model', values: this.models.map((m) => ({ id: m.value, label: m.displayName })), current: this.model },
      ...(efforts.length > 0 ? [{ id: 'effort', label: 'Reasoning effort', values: efforts.map((id) => ({ id, label: id })), current: this.effort }] : []),
    ];
  }

  send(text: string) {
    this.turning = true;
    this.interrupting = false;
    this.input.push(text);
  }

  answer(approvalId: string, choiceId: string) {
    const ask = this.pending.get(approvalId);
    if (ask === undefined) throw new ChatRefused('That approval is not pending any more');
    const suggestion = choiceId.startsWith('suggestion:') ? ask.suggestions[Number(choiceId.slice('suggestion:'.length))] : undefined;
    if (choiceId === 'deny') ask.resolve({ behavior: 'deny', message: 'The user declined this.' });
    else if (choiceId === 'allow') ask.resolve({ behavior: 'allow', updatedInput: ask.input });
    else if (suggestion) ask.resolve({ behavior: 'allow', updatedInput: ask.input, updatedPermissions: [suggestion] });
    else throw new ChatRefused('That is not one of the choices');
    this.pending.delete(approvalId);
    this.emit({ kind: 'approval_answered', approvalId, choiceId });
  }

  async interrupt() {
    if (!this.turning) return;
    this.interrupting = true;
    this.denyPending();
    await this.query.interrupt();
    // The turn ends at its `result`; wait for it, so the host never sees the next turn start before this one's end.
    for (let waited = 0; this.turning && waited < 5_000; waited += 50) await new Promise((resolve) => setTimeout(resolve, 50));
  }

  async setOption(id: string, value: string) {
    const option = this.options.find((o) => o.id === id);
    if (option === undefined) throw new ChatRefused(`There is no option "${id}"`);
    if (!option.values.some((v) => v.id === value)) throw new ChatRefused(`"${value}" is not a value of ${id}`);
    if (id === 'permissionMode') {
      await this.query.setPermissionMode(value as never);
      this.mode = value;
    } else if (id === 'model') {
      await this.query.setModel(value === 'default' ? undefined : value);
      this.model = value;
    } else {
      if (this.turning) throw new ChatRefused('The reasoning effort can only change between turns');
      this.hidden++;
      this.input.push(`/effort ${value}`);
      this.effort = value;
    }
    this.emit({ kind: 'option', id, value });
  }

  async close() {
    if (this.closing) return;
    this.closing = true;
    this.denyPending();
    this.input.end();
    this.query?.close();
    if (this.pid !== undefined) await endGroup(this.pid);
  }

  onEvent(listener: (event: ChatEvent) => void) {
    this.listeners.push(listener);
  }

  private emit(...events: ChatEvent[]) {
    for (const event of events) for (const listener of this.listeners) listener(event);
  }

  private denyPending() {
    for (const ask of this.pending.values()) ask.resolve({ behavior: 'deny', message: 'The turn was interrupted.', interrupt: true });
    this.pending.clear();
  }

  private ask(approvalId: string, tool: string, input: Record<string, unknown>, suggestions: PermissionUpdate[], title?: string): Promise<PermissionResult> {
    const choices: ChatChoice[] = [
      { id: 'allow', label: 'Allow', allow: true },
      { id: 'deny', label: 'Deny', allow: false },
      ...suggestions.map((s, i) => ({ id: `suggestion:${i}`, label: labelOf(s), allow: true })),
    ];
    return new Promise((resolve) => {
      this.pending.set(approvalId, { input, suggestions, resolve });
      this.emit({ kind: 'approval', approvalId, tool, arg: argOf(input) ?? title, choices });
    });
  }

  private async pump() {
    try {
      for await (const message of this.query) {
        try {
          this.emit(...this.translate(message));
        } catch (error) {
          log.error('a claude message could not be handled', error);
        }
      }
    } catch (error) {
      if (!this.closing) log.error('the claude stream failed', error);
    }
    if (this.closing) return;
    // The process ended on its own: that is the end of the turn that was running.
    this.emit({ kind: 'error', text: 'The Claude process ended' });
    if (this.turning) this.emit({ kind: 'turn_end', outcome: 'error', model: this.lastModel });
    this.turning = false;
  }

  /** The events of one SDK message. Never throws on a shape it does not know: that message gives none. */
  private translate(message: SDKMessage): ChatEvent[] {
    const m = message as { type: string; subtype?: string; session_id?: string; [key: string]: any };
    if (typeof m.session_id === 'string') this.nativeId = m.session_id;
    if (m.type === 'result') return this.turnEnd(m);
    if (this.hidden > 0) return [];
    switch (m.type) {
      case 'system':
        if (m.subtype === 'init' && typeof m.permissionMode === 'string') this.mode = m.permissionMode;
        if (m.subtype === 'status' && typeof m.permissionMode === 'string' && m.permissionMode !== this.mode) {
          this.mode = m.permissionMode;
          return [{ kind: 'option', id: 'permissionMode', value: this.mode }];
        }
        return [];
      case 'stream_event': {
        const delta = m.event?.type === 'content_block_delta' && m.event.delta?.type === 'text_delta' ? m.event.delta.text : undefined;
        return typeof delta === 'string' && delta !== '' ? [{ kind: 'delta', text: delta }] : [];
      }
      case 'assistant': {
        if (typeof m.message?.model === 'string') this.lastModel = m.message.model;
        const events: ChatEvent[] = [];
        for (const block of Array.isArray(m.message?.content) ? m.message.content : []) {
          if (block?.type === 'text' && typeof block.text === 'string' && block.text !== '') events.push({ kind: 'assistant', text: block.text });
          if (block?.type === 'tool_use' && typeof block.id === 'string') {
            this.tools.set(block.id, String(block.name));
            events.push({ kind: 'tool_start', callId: block.id, tool: String(block.name), arg: argOf(block.input) });
          }
        }
        return events;
      }
      case 'user': {
        const events: ChatEvent[] = [];
        for (const block of Array.isArray(m.message?.content) ? m.message.content : []) {
          if (block?.type !== 'tool_result' || typeof block.tool_use_id !== 'string') continue;
          events.push({ kind: 'tool_end', callId: block.tool_use_id, tool: this.tools.get(block.tool_use_id) ?? '', output: textOf(block.content).split('\n'), status: block.is_error ? 'err' : 'ok' });
        }
        return events;
      }
      default:
        return [];
    }
  }

  private turnEnd(m: { subtype?: string; is_error?: boolean; errors?: unknown; usage?: unknown; total_cost_usd?: unknown; modelUsage?: unknown }): ChatEvent[] {
    if (this.hidden > 0) {
      this.hidden--;
      return [];
    }
    const interrupted = this.interrupting;
    this.turning = false;
    this.interrupting = false;
    const events: ChatEvent[] = [];
    if (m.is_error && !interrupted) events.push({ kind: 'error', text: Array.isArray(m.errors) && m.errors.length > 0 ? m.errors.join('\n') : 'The turn failed' });
    const usage: ChatUsage = {};
    for (const [key, value] of Object.entries((m.usage ?? {}) as Record<string, unknown>)) if (typeof value === 'number') usage[key] = value;
    if (typeof m.total_cost_usd === 'number') usage.total_cost_usd = m.total_cost_usd;
    const model = this.lastModel ?? Object.keys((m.modelUsage ?? {}) as object)[0];
    events.push({ kind: 'turn_end', outcome: interrupted ? 'interrupted' : m.is_error ? 'error' : 'ok', model, usage });
    return events;
  }
}

/** Messages the person typed, as the stream the SDK reads; it ends when the conversation closes. */
function inputQueue() {
  const waiting: SDKUserMessage[] = [];
  let wake: (() => void) | undefined;
  let ended = false;
  return {
    push(text: string) {
      waiting.push({ type: 'user', message: { role: 'user', content: text }, parent_tool_use_id: null });
      wake?.();
    },
    end() {
      ended = true;
      wake?.();
    },
    iterable: (async function* () {
      while (true) {
        const next = waiting.shift();
        if (next !== undefined) yield next;
        else if (ended) return;
        else await new Promise<void>((resolve) => void (wake = resolve));
      }
    })(),
  };
}

const textOf = (content: unknown): string =>
  typeof content === 'string' ? content : Array.isArray(content) ? content.map((c) => (typeof c?.text === 'string' ? c.text : '')).join('\n') : '';

/** What a tool call is about, in one string: the command, the path, the pattern, else its input as JSON. */
const argOf = (input: unknown): string | undefined => {
  if (typeof input !== 'object' || input === null) return undefined;
  const fields = input as Record<string, unknown>;
  const main = [fields.command, fields.file_path, fields.path, fields.pattern, fields.url].find((v) => typeof v === 'string');
  return typeof main === 'string' ? main : JSON.stringify(input);
};

const labelOf = (update: PermissionUpdate): string => {
  switch (update.type) {
    case 'addRules':
      return `Always allow ${update.rules.map((r) => r.ruleContent ?? r.toolName).join(', ')}`;
    case 'addDirectories':
      return `Allow ${update.directories.join(', ')}`;
    case 'setMode':
      return `Allow and switch to ${update.mode}`;
    default:
      return 'Allow and change the permissions';
  }
};
