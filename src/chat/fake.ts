import { mkdirSync, rmSync } from 'node:fs';
import type { Git, GitResult } from './git.ts';
import { ChatRefused, type ChatConversation, type ChatEvent, type ChatOption, type ChatRunner } from './runner.ts';

/**
 * A conversation that plays what a test tells it: `reply` runs on each message sent, `emit` plays an event any time
 * (a turn ends on cue, an approval is asked and stays pending until `answer` is called).
 */
export class FakeConversation implements ChatConversation {
  options: ChatOption[] = [];
  nativeId: string | undefined;
  process: ChatConversation['process'];
  sent: string[] = [];
  answers: { approvalId: string; choiceId: string }[] = [];
  closed = false;
  /** Events to play when a message arrives. */
  reply: (text: string, conversation: FakeConversation) => void = () => {};
  private listeners: ((event: ChatEvent) => void)[] = [];
  private endListeners: (() => void)[] = [];

  send(text: string) {
    this.sent.push(text);
    this.reply(text, this);
  }
  answer(approvalId: string, choiceId: string) {
    this.answers.push({ approvalId, choiceId });
    this.emit({ kind: 'approval_answered', approvalId, choiceId });
  }
  interrupts = 0;
  /** Plays what the provider does on an interrupt; by default nothing, as an adapter that never says the turn ended. */
  onInterrupt: (conversation: FakeConversation) => void = () => {};
  async interrupt() {
    this.interrupts++;
    this.onInterrupt(this);
  }
  async setOption(id: string, value: string) {
    const option = this.options.find((o) => o.id === id);
    if (option) option.current = value;
    this.emit({ kind: 'option', id, value });
  }
  async close() {
    this.closed = true;
  }
  onEvent(listener: (event: ChatEvent) => void) {
    this.listeners.push(listener);
  }
  onEnd(listener: () => void) {
    this.endListeners.push(listener);
  }
  /** Plays the agent's process ending on its own: the error (and the end of a running turn) as an adapter says them, then the end. */
  die(...events: ChatEvent[]) {
    this.emit(...events);
    for (const listener of this.endListeners) listener();
  }
  emit(...events: ChatEvent[]) {
    for (const event of events) for (const listener of this.listeners) listener(event);
  }
}

/** A runner with no provider behind it: it hands out `FakeConversation`s and remembers what it was asked. */
export class FakeChatRunner implements ChatRunner {
  opened: Parameters<ChatRunner['open']>[0][] = [];
  conversations: FakeConversation[] = [];
  /** Set to make `open` refuse, as a provider that is not installed does. */
  refuseWith: string | undefined;
  /** Applied to each new conversation, to script its answers. */
  setup: (conversation: FakeConversation) => void = () => {};

  async open(args: Parameters<ChatRunner['open']>[0]) {
    this.opened.push(args);
    if (this.refuseWith !== undefined) throw new ChatRefused(this.refuseWith);
    const conversation = new FakeConversation();
    this.setup(conversation);
    this.conversations.push(conversation);
    return conversation;
  }
}

/** A repository the fake knows: what git would say about the folder it is the table entry of. */
export type FakeRepo = {
  bare?: boolean;
  /** The folder is a linked worktree of another repository. */
  linked?: boolean;
  /** The URL of `origin`; none when absent. */
  origin?: string;
  /** The branch checked out; null for a detached HEAD. */
  head: string | null;
  branches: string[];
  /** Remote branches without the `origin/` prefix. */
  remoteBranches?: string[];
  /** What `origin/HEAD` points at, without the prefix. */
  originHead?: string;
  /** The lines `git status --porcelain` prints. */
  status?: string[];
  /** Where git says FETCH_HEAD is, when a test wants a fetch time. */
  fetchHead?: string;
  /** The folders of the linked worktrees git made here, with their branches: `worktree add` fills it and `worktree remove` empties it. */
  worktrees?: { path: string; branch: string }[];
};

/** A git with a table of folders and the repositories in them, which answers the commands the host sends, and plays scripted failures. */
export class FakeGit implements Git {
  repos = new Map<string, FakeRepo>();
  /** Every command run, in order. */
  calls: { folder: string; args: string[]; timeoutMs?: number }[] = [];
  /** Commands that fail instead of answering, by their arguments joined with a space. */
  failures = new Map<string, Extract<GitResult, { ok: false }>>();

  async run(folder: string, args: string[], options?: { timeoutMs?: number }): Promise<GitResult> {
    this.calls.push({ folder, args, timeoutMs: options?.timeoutMs });
    const failure = this.failures.get(args.join(' '));
    if (failure !== undefined) return failure;
    const repo = this.repos.get(folder);
    if (repo === undefined) return { ok: false, code: 128, stderr: 'fatal: not a git repository' };
    const out = (...printed: string[]) => ({ ok: true as const, out: printed.map((line) => `${line}\n`).join('') });
    const no = { ok: false as const, code: 1, stderr: '' };
    const [verb, ...rest] = args[0] === '--no-optional-locks' ? args.slice(1) : args;
    if (verb === 'rev-parse' && rest.includes('--verify')) return [...repo.branches.map((name) => `refs/heads/${name}`), ...(repo.remoteBranches ?? []).map((name) => `refs/remotes/origin/${name}`)].includes(rest.at(-1)!) ? out(rest.at(-1)!) : no;
    if (verb === 'worktree' && rest[0] === 'add') {
      // worktree add --no-track -b <branch> <path> <start>: the branch and the folder appear, as git makes them
      const [branch, path, start] = rest.slice(3);
      const known = [...repo.branches.map((name) => `refs/heads/${name}`), ...(repo.remoteBranches ?? []).map((name) => `refs/remotes/origin/${name}`)];
      if (repo.branches.includes(branch!) || known.includes(start!) === false) return { ok: false, code: 128, stderr: 'fatal: invalid reference' };
      mkdirSync(path!, { recursive: true });
      repo.branches.push(branch!);
      (repo.worktrees ??= []).push({ path: path!, branch: branch! });
      return out();
    }
    if (verb === 'worktree' && rest[0] === 'remove') {
      rmSync(rest.at(-1)!, { recursive: true, force: true });
      repo.worktrees = (repo.worktrees ?? []).filter((worktree) => worktree.path !== rest.at(-1));
      return out();
    }
    if (verb === 'worktree' && rest[0] === 'prune') return out();
    if (verb === 'branch' && rest[0] === '-D') {
      if (repo.branches.includes(rest[1]!) === false) return { ok: false, code: 1, stderr: 'error: branch not found' };
      repo.branches = repo.branches.filter((name) => name !== rest[1]);
      return out();
    }
    if (verb === 'rev-parse') return out(String(repo.bare === true), repo.linked ? '/elsewhere/.git/worktrees/w' : '.git', repo.linked ? '/elsewhere/.git' : '.git', repo.fetchHead ?? '.git/FETCH_HEAD');
    if (verb === 'config') return repo.origin === undefined ? no : out(repo.origin);
    if (verb === 'symbolic-ref' && rest.includes('refs/remotes/origin/HEAD')) return repo.originHead === undefined ? no : out(`refs/remotes/origin/${repo.originHead}`);
    if (verb === 'symbolic-ref') return repo.head === null ? no : out(repo.head);
    if (verb === 'for-each-ref') return out(...repo.branches.map((name) => `refs/heads/${name}`), ...(repo.remoteBranches ?? []).map((name) => `refs/remotes/origin/${name}`), ...(repo.originHead === undefined ? [] : ['refs/remotes/origin/HEAD']));
    if (verb === 'fetch') return out();
    if (verb === 'status') return out(...(repo.status ?? []));
    return { ok: false, code: 129, stderr: `the fake git does not know ${verb}` };
  }
}
