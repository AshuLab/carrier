import { execFile, spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { createScopedLogger } from '@ashulab/universal-logger';
import { endGroup, resolveAgentBinary } from './group.ts';
import { ChatRefused, type ChatChoice, type ChatConversation, type ChatEvent, type ChatOption, type ChatRunner, type ChatUsage } from './runner.ts';

// The Codex adapter of the chat runner: the user's own `codex app-server`, JSON-RPC over stdio, one JSON object per
// line (docs/research/chat-spike.md). No npm dependency: the adapter spawns the binary and speaks the protocol itself.
//
// Written against codex-cli / app-server 0.153.4, which Codex marks as experimental: the protocol changes with the
// version. The messages below are the ones the spike recorded; a notification this adapter does not know gives no
// event, and a server request it does not know is answered with an error so that it never holds a turn. A version other
// than this one is logged when the server says hello.
export const CODEX_APP_SERVER_VERSION = '0.153.4';

const log = createScopedLogger('chat');

const APPROVAL_POLICIES = [
  { id: 'untrusted', label: 'Ask unless the command is known to be safe' },
  { id: 'on-request', label: 'The agent decides when to ask' },
  { id: 'never', label: 'Never ask' },
];
// `danger-full-access` is left out, as Claude's `bypassPermissions` is: Carrier does not turn it on.
const SANDBOXES = [
  { id: 'read-only', label: 'Read only' },
  { id: 'workspace-write', label: 'Write in the folder' },
];
/** A turn takes the sandbox as an object, a thread as a name. */
const SANDBOX_POLICIES: Record<string, unknown> = {
  'read-only': { type: 'readOnly', networkAccess: false },
  'workspace-write': { type: 'workspaceWrite', writableRoots: [], networkAccess: false, excludeTmpdirEnvVar: false, excludeSlashTmp: false },
};

/** The lines of one `codex app-server` process. Absent from tests, where the recording plays the server. */
export type CodexTransport = {
  pid?: number;
  write(line: string): void;
  onLine(listener: (line: string) => void): void;
  /** Called once, when the process has ended or could not be started. */
  onExit(listener: () => void): void;
};

export type CodexChatDeps = {
  /** The `codex` to run: `command` when given, else the one found on the path. Throws when there is none. */
  resolve: (command: string | undefined, env: NodeJS.ProcessEnv) => string;
  /** Whether the user is logged in to the binary. */
  loggedIn: (binary: string, env: NodeJS.ProcessEnv) => Promise<boolean>;
  /** Starts `<binary> app-server` as the leader of its own process group. */
  spawn: (binary: string, options: { cwd: string; env: NodeJS.ProcessEnv }) => CodexTransport;
};

const codexLoggedIn = (binary: string, env: NodeJS.ProcessEnv) =>
  new Promise<boolean>((done) => {
    execFile(binary, ['login', 'status'], { env, timeout: 15_000 }, (error) => done(error === null)); // what it prints is not read: it names the login
  });

const ownGroup: CodexChatDeps['spawn'] = (binary, { cwd, env }) => {
  const child = spawn(binary, ['app-server'], { cwd, env, stdio: ['pipe', 'pipe', 'pipe'], detached: true });
  child.stderr.resume(); // drained and never read: it may say things about the login
  child.stdin.on('error', () => {}); // a write after the process ended; `onExit` reports the end
  const lines = createInterface({ input: child.stdout });
  return {
    pid: child.pid,
    write: (line) => void child.stdin.write(`${line}\n`),
    onLine: (listener) => void lines.on('line', listener),
    onExit(listener) {
      let called = false;
      const once = () => called || ((called = true), listener());
      child.once('error', once);
      child.once('close', once);
    },
  };
};

export const realCodexDeps: CodexChatDeps = { resolve: (command, env) => resolveAgentBinary('codex', command, env), loggedIn: codexLoggedIn, spawn: ownGroup };

export function codexChatRunner(deps: CodexChatDeps = realCodexDeps): ChatRunner {
  return {
    async open({ folder, resume, options = {}, command, env }) {
      let binary: string;
      try {
        binary = deps.resolve(command, env);
      } catch {
        throw new ChatRefused(`Codex is not installed: ${command === undefined ? 'there is no "codex" on the path' : `"${command}" cannot be run`}`);
      }
      if (!(await deps.loggedIn(binary, env))) throw new ChatRefused('Codex is not logged in; run "codex login" once to log in');
      const conversation = new CodexConversation(options, binary);
      try {
        await conversation.start(deps, { folder, env, resume });
      } catch (error) {
        log.error('codex could not be started', error);
        await conversation.close();
        throw new ChatRefused(resume === undefined ? 'Codex could not be started' : 'Codex could not resume that conversation');
      }
      return conversation;
    },
  };
}

class CodexConversation implements ChatConversation {
  nativeId: string | undefined;
  private listeners: ((event: ChatEvent) => void)[] = [];
  private endListeners: (() => void)[] = [];
  private transport!: CodexTransport;
  private nextId = 1;
  private waiting = new Map<number, { resolve: (result: any) => void; reject: (error: Error) => void }>();
  /** Approvals asked and not answered: the server's request id, and the decision each choice answers with. */
  private pending = new Map<string, { requestId: number; decisions: Record<string, unknown> }>();
  private models: { model: string; displayName: string; defaultReasoningEffort?: string; supportedReasoningEfforts: { reasoningEffort: string }[] }[] = [];
  private model: string;
  private effort: string;
  private approvalPolicy: string;
  private sandbox: string;
  /** What changed since the last turn: Codex applies it from the next `turn/start`, and keeps it after. */
  private overrides: Record<string, unknown> = {};
  private turning = false;
  private turnId: string | undefined;
  private usage: ChatUsage = {};
  private closing = false;
  private chosen: Record<string, string>;
  private binary: string;

  constructor(chosen: Record<string, string>, binary: string) {
    this.chosen = chosen;
    this.binary = binary;
    this.model = chosen.model ?? '';
    this.effort = chosen.effort ?? '';
    this.approvalPolicy = chosen.approvalPolicy ?? 'untrusted'; // every command that is not known to be safe asks, as Claude's default mode does
    this.sandbox = chosen.sandbox ?? 'workspace-write';
  }

  async start(deps: CodexChatDeps, { folder, env, resume }: { folder: string; env: NodeJS.ProcessEnv; resume: string | undefined }) {
    this.transport = deps.spawn(this.binary, { cwd: folder, env });
    this.transport.onLine((line) => this.receive(line));
    this.transport.onExit(() => this.ended());
    const hello = await this.request('initialize', { clientInfo: { name: 'carrier', title: 'Carrier', version: '0.0.0' } });
    const version = /\/(\d+\.\d+\.\d+)/.exec(String(hello?.userAgent))?.[1];
    if (version !== CODEX_APP_SERVER_VERSION) log.warn('codex app-server is not the version this adapter was written against', { found: version, expected: CODEX_APP_SERVER_VERSION });
    this.notify('initialized');
    const params = { cwd: folder, approvalPolicy: this.approvalPolicy, sandbox: this.sandbox, ...(this.chosen.model && { model: this.chosen.model }) };
    const started = await this.request(resume === undefined ? 'thread/start' : 'thread/resume', resume === undefined ? params : { threadId: resume, ...params });
    this.nativeId = started.thread.id;
    this.model = this.chosen.model ?? started.model ?? '';
    this.effort = this.chosen.effort ?? started.reasoningEffort ?? '';
    if (this.chosen.effort) this.overrides.effort = this.chosen.effort; // a thread takes no effort: the first turn carries it
    this.models = (await this.request('model/list', {})).data.filter((m: { hidden?: boolean }) => !m.hidden);
  }

  get process() {
    return this.transport?.pid === undefined ? undefined : { pid: this.transport.pid, pgid: this.transport.pid, command: this.binary }; // it leads its own group (`ownGroup`)
  }

  get options(): ChatOption[] {
    const efforts = this.effortsOf(this.model);
    return [
      { id: 'approvalPolicy', label: 'Approvals', values: APPROVAL_POLICIES, current: this.approvalPolicy },
      { id: 'sandbox', label: 'Sandbox', values: SANDBOXES, current: this.sandbox },
      { id: 'model', label: 'Model', values: this.models.map((m) => ({ id: m.model, label: m.displayName, version: m.model })), current: this.model },
      ...(efforts.length > 0 ? [{ id: 'effort', label: 'Reasoning effort', values: efforts.map((id) => ({ id, label: id })), current: this.effort }] : []),
    ];
  }

  private effortsOf = (model: string) => this.models.find((m) => m.model === model)?.supportedReasoningEfforts.map((e) => e.reasoningEffort) ?? [];

  send(text: string) {
    this.turning = true;
    this.usage = {};
    this.turnId = undefined;
    const overrides = this.overrides;
    this.overrides = {};
    this.request('turn/start', { threadId: this.nativeId, input: [{ type: 'text', text, text_elements: [] }], ...overrides }).then(
      (started) => {
        if (this.turning && this.turnId === undefined) this.turnId = started?.turn?.id;
      },
      (error) => {
        if (this.closing) return;
        log.error('codex did not start the turn', error);
        this.emit({ kind: 'error', text: 'Codex did not start the turn' }, { kind: 'turn_end', outcome: 'error', model: this.model });
        this.turning = false;
      },
    );
  }

  answer(approvalId: string, choiceId: string) {
    const ask = this.pending.get(approvalId);
    if (ask === undefined) throw new ChatRefused('That approval is not pending any more');
    if (!(choiceId in ask.decisions)) throw new ChatRefused('That is not one of the choices');
    this.pending.delete(approvalId);
    this.emit({ kind: 'approval_answered', approvalId, choiceId });
    this.respond(ask.requestId, { decision: ask.decisions[choiceId] });
  }

  async interrupt() {
    if (!this.turning) return;
    this.denyPending();
    for (let waited = 0; this.turnId === undefined && this.turning && waited < 2_000; waited += 50) await new Promise((resolve) => setTimeout(resolve, 50));
    if (this.turnId !== undefined && this.turning) await this.request('turn/interrupt', { threadId: this.nativeId, turnId: this.turnId });
    // The turn ends at its `turn/completed`; wait for it, so the host never sees the next turn start before this one's end.
    for (let waited = 0; this.turning && waited < 5_000; waited += 50) await new Promise((resolve) => setTimeout(resolve, 50));
  }

  async setOption(id: string, value: string) {
    const option = this.options.find((o) => o.id === id);
    if (option === undefined) throw new ChatRefused(`There is no option "${id}"`);
    if (!option.values.some((v) => v.id === value)) throw new ChatRefused(`"${value}" is not a value of ${id}`);
    const events: ChatEvent[] = [{ kind: 'option', id, value }];
    if (id === 'model') {
      this.model = value;
      this.overrides.model = value;
      // A level the new model does not list cannot stay.
      const efforts = this.effortsOf(value);
      if (efforts.length > 0 && !efforts.includes(this.effort)) {
        this.effort = this.models.find((m) => m.model === value)?.defaultReasoningEffort ?? efforts[0]!;
        this.overrides.effort = this.effort;
        events.push({ kind: 'option', id: 'effort', value: this.effort });
      }
    } else if (id === 'effort') {
      this.effort = value;
      this.overrides.effort = value;
    } else if (id === 'approvalPolicy') {
      this.approvalPolicy = value;
      this.overrides.approvalPolicy = value;
    } else {
      this.sandbox = value;
      this.overrides.sandboxPolicy = SANDBOX_POLICIES[value];
    }
    this.emit(...events);
  }

  async close() {
    if (this.closing) return;
    this.closing = true;
    this.denyPending();
    this.rejectWaiting();
    if (this.transport?.pid !== undefined) await endGroup(this.transport.pid);
  }

  onEvent(listener: (event: ChatEvent) => void) {
    this.listeners.push(listener);
  }

  onEnd(listener: () => void) {
    this.endListeners.push(listener);
  }

  private emit(...events: ChatEvent[]) {
    for (const event of events) for (const listener of this.listeners) listener(event);
  }

  private denyPending() {
    for (const ask of this.pending.values()) this.respond(ask.requestId, { decision: 'cancel' });
    this.pending.clear();
  }

  private rejectWaiting() {
    for (const call of this.waiting.values()) call.reject(new Error('The Codex process ended'));
    this.waiting.clear();
  }

  private ended() {
    this.rejectWaiting();
    if (this.closing) return;
    // The process ended on its own: that is the end of the turn that was running.
    this.emit({ kind: 'error', text: 'The Codex process ended' });
    if (this.turning) this.emit({ kind: 'turn_end', outcome: 'error', model: this.model });
    this.turning = false;
    for (const listener of this.endListeners) listener();
  }

  private request(method: string, params: unknown) {
    const id = this.nextId++;
    return new Promise<any>((resolve, reject) => {
      this.waiting.set(id, { resolve, reject });
      this.transport.write(JSON.stringify({ id, method, params }));
    });
  }

  private notify(method: string) {
    this.transport.write(JSON.stringify({ method }));
  }

  private respond(id: number, result: unknown) {
    this.transport.write(JSON.stringify({ id, result }));
  }

  /** One line from the server. Never throws: a line it cannot read or does not know gives no event. */
  private receive(line: string) {
    try {
      const m = JSON.parse(line) as { id?: number; method?: unknown; params?: any; result?: unknown; error?: { message?: unknown } };
      if (typeof m.method === 'string' && m.id !== undefined) this.serverRequest(m.id, m.method, m.params);
      else if (typeof m.method === 'string') this.emit(...this.translate(m.method, m.params));
      else if (m.id !== undefined) {
        const call = this.waiting.get(m.id);
        this.waiting.delete(m.id);
        if (m.error === undefined) call?.resolve(m.result);
        else call?.reject(new Error(`codex answered with an error: ${String(m.error?.message)}`));
      }
    } catch (error) {
      log.error('a codex message could not be handled', error);
    }
  }

  private serverRequest(requestId: number, method: string, params: any) {
    if (method !== 'item/commandExecution/requestApproval') {
      // A request left unanswered holds the turn: say the method is not there.
      log.warn('codex asked for something this adapter does not handle', { method });
      this.transport.write(JSON.stringify({ id: requestId, error: { code: -32601, message: `Method not supported: ${method}` } }));
      return;
    }
    const listed: unknown[] = Array.isArray(params?.availableDecisions) ? params.availableDecisions : [];
    const amendment = listed.find((d) => typeof d === 'object' && d !== null && 'acceptWithExecpolicyAmendment' in d);
    const decisions: Record<string, unknown> = { accept: 'accept', decline: 'decline' }; // `decline` is not listed and works
    const choices: ChatChoice[] = [
      { id: 'accept', label: 'Allow', allow: true },
      { id: 'decline', label: 'Deny', allow: false },
    ];
    if (amendment !== undefined) {
      decisions.amend = amendment;
      choices.push({ id: 'amend', label: `Always allow ${Array.isArray(params.proposedExecpolicyAmendment) ? params.proposedExecpolicyAmendment.join(' ') : 'this command'}`, allow: true });
    }
    if (listed.includes('cancel')) {
      decisions.cancel = 'cancel';
      choices.push({ id: 'cancel', label: 'Deny and stop the turn', allow: false });
    }
    const approvalId = String(requestId);
    this.pending.set(approvalId, { requestId, decisions });
    this.emit({ kind: 'approval', approvalId, tool: 'command', arg: typeof params?.command === 'string' ? params.command : undefined, choices });
  }

  private translate(method: string, params: any): ChatEvent[] {
    switch (method) {
      case 'turn/started':
        if (typeof params?.turn?.id === 'string') this.turnId = params.turn.id;
        return [];
      case 'serverRequest/resolved':
        this.pending.delete(String(params?.requestId)); // answered elsewhere, or by the end of the turn
        return [];
      case 'item/agentMessage/delta':
        return typeof params?.delta === 'string' && params.delta !== '' ? [{ kind: 'delta', text: params.delta }] : [];
      case 'item/started': {
        const item = params?.item;
        return item?.type === 'commandExecution' && typeof item.id === 'string' ? [{ kind: 'tool_start', callId: item.id, tool: 'command', arg: typeof item.command === 'string' ? item.command : undefined }] : [];
      }
      case 'item/completed': {
        const item = params?.item;
        if (item?.type === 'agentMessage' && typeof item.text === 'string' && item.text !== '') return [{ kind: 'assistant', text: item.text }];
        if (item?.type !== 'commandExecution' || typeof item.id !== 'string') return [];
        return [{ kind: 'tool_end', callId: item.id, tool: 'command', ...(typeof item.aggregatedOutput === 'string' && { output: item.aggregatedOutput.split('\n') }), status: item.status === 'completed' && item.exitCode === 0 ? 'ok' : 'err' }];
      }
      case 'thread/tokenUsage/updated':
        // One update per model call: the turn's usage is what its calls added up to.
        for (const [key, value] of Object.entries((params?.tokenUsage?.last ?? {}) as Record<string, unknown>)) if (typeof value === 'number') this.usage[key] = (this.usage[key] ?? 0) + value;
        return [];
      case 'turn/completed':
        return this.turnEnd(params?.turn);
      default:
        return [];
    }
  }

  private turnEnd(turn: { status?: unknown; error?: { message?: unknown } } | undefined): ChatEvent[] {
    const outcome = turn?.status === 'completed' ? 'ok' : turn?.status === 'interrupted' ? 'interrupted' : 'error';
    const usage = this.usage;
    this.turning = false;
    this.turnId = undefined;
    this.usage = {};
    const events: ChatEvent[] = [];
    if (outcome === 'error') events.push({ kind: 'error', text: typeof turn?.error?.message === 'string' ? turn.error.message : 'The turn failed' });
    events.push({ kind: 'turn_end', outcome, model: this.model, usage });
    return events;
  }
}
