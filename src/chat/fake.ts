import { mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { FakeClock } from '../orchestration/fake.ts';
import type { Git, GitResult } from './git.ts';
import type { Shell, ShellResult } from './shell.ts';
import { createProjects, type GithubRepos } from './projects.ts';
import { noGeneratorChosen, TextGeneratorFailed, type TextGenerator } from './text-generator.ts';
import { ChatRefused, type ChatCommand, type ChatConversation, type ChatEvent, type ChatOption, type ChatRunner } from './runner.ts';

/**
 * A conversation that plays what a test tells it: `reply` runs on each message sent, `emit` plays an event any time
 * (a turn ends on cue, an approval is asked and stays pending until `answer` is called).
 */
export class FakeConversation implements ChatConversation {
  options: ChatOption[] = [];
  nativeId: string | undefined;
  startedOver = false;
  mcpProblem: string | undefined;
  /** What the fake says its Codex app-server is; a test sets it with `setup`. */
  appServerVersion: string | undefined;
  process: ChatConversation['process'];
  sent: string[] = [];
  answers: { approvalId: string; choiceId: string; answers?: Record<string, string> }[] = [];
  closed = false;
  /** Events to play when a message arrives. */
  reply: (text: string, conversation: FakeConversation) => void = () => {};
  private listeners: ((event: ChatEvent) => void)[] = [];
  private endListeners: (() => void)[] = [];

  /** What the fake lists for the person to invoke; the commands each message invoked go to `invoked`. */
  commands: ChatCommand[] = [];
  invoked: (string | undefined)[] = [];
  send(text: string, command?: ChatCommand) {
    this.invoked.push(command?.id);
    this.sent.push(text);
    this.reply(text, this);
  }
  answer(approvalId: string, choiceId: string, answers?: Record<string, string>) {
    this.answers.push({ approvalId, choiceId, ...(answers && { answers }) });
    this.emit({ kind: 'approval_answered', approvalId, choiceId, ...(answers && { answers }) });
  }
  interrupts = 0;
  /** Plays what the provider does on an interrupt; by default nothing, as an adapter that never says the turn ended. */
  onInterrupt: (conversation: FakeConversation) => void = () => {};
  async interrupt() {
    this.interrupts++;
    this.onInterrupt(this);
  }
  stopped: string[] = [];
  async stopTask(taskId: string) {
    this.stopped.push(taskId);
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
  /** Set to make only the nth `open` (1 is the first) refuse, as a provider that fails once does; the others open. */
  refuseOpen: { nth: number; with: string } | undefined;
  /** Applied to each new conversation, to script its answers. */
  setup: (conversation: FakeConversation) => void = () => {};

  async open(args: Parameters<ChatRunner['open']>[0]) {
    this.opened.push(args);
    if (this.refuseWith !== undefined) throw new ChatRefused(this.refuseWith);
    if (this.refuseOpen?.nth === this.opened.length) throw new ChatRefused(this.refuseOpen.with);
    const conversation = new FakeConversation();
    this.setup(conversation);
    this.conversations.push(conversation);
    return conversation;
  }
}

/**
 * A text generator that plays what a test tells it: `answer` is what it says (a string), `fail` makes it reject with that reason,
 * `hang` makes it never answer. The calls it got are in `calls`, and `active` is how many are in flight at once at most.
 */
export class FakeTextGenerator implements TextGenerator {
  answer = 'A title';
  fail: string | undefined;
  hang = false;
  calls: { system: string; text: string }[] = [];
  running = 0;
  /** The most calls that were in flight at the same time. */
  mostRunning = 0;
  /** Set to hold each answer until the test calls it; the answer then goes out. */
  held: (() => void)[] | undefined;

  chosen() {
    if (this.fail === noGeneratorChosen) throw new TextGeneratorFailed(noGeneratorChosen);
  }

  async generate(input: { system: string; text: string }) {
    this.calls.push(input);
    this.mostRunning = Math.max(this.mostRunning, ++this.running);
    try {
      if (this.hang) await new Promise<never>(() => {});
      if (this.held !== undefined) await new Promise<void>((release) => this.held!.push(release));
      if (this.fail !== undefined) throw new TextGeneratorFailed(this.fail);
      return this.answer;
    } finally {
      this.running--;
    }
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
  /** The commits of each branch that no other branch contains, for `rev-list --count`; 0 when absent. */
  unpushed?: Record<string, number>;
  /** The commits of `origin/<branch>` that the local branch lacks, for `rev-list --count refs/heads/<branch>..refs/remotes/origin/<branch>`; 0 when absent. */
  behind?: Record<string, number>;
  /** The commits of the local branch that `origin/<branch>` lacks, for `rev-list --left-right --count refs/heads/<branch>...refs/remotes/origin/<branch>`; 0 when absent. The two print the same commit when both counts are 0. */
  ahead?: Record<string, number>;
};

/** A git with a table of folders and the repositories in them, which answers the commands the host sends, and plays scripted failures. */
export class FakeGit implements Git {
  repos = new Map<string, FakeRepo>();
  /** Every command run, in order. */
  calls: { folder: string; args: string[]; timeoutMs?: number; env?: NodeJS.ProcessEnv }[] = [];
  /** While set, a `clone` waits for it (or for its signal to abort) before it ends: a clone that is still running. */
  clonePending: Promise<void> | undefined;
  /** While set, a `worktree add` waits for it (or for its signal to abort) before it makes anything: a worktree that is still being made. */
  worktreePending: Promise<void> | undefined;
  /** Commands that fail instead of answering, by their arguments joined with a space. */
  failures = new Map<string, Extract<GitResult, { ok: false }>>();
  /** What a repository is when it has just been cloned, besides its origin: `head` and `branches` are `main` unless this says otherwise. */
  cloned: Partial<FakeRepo> = {};
  /** What `ssh -G` says the host of each alias is; a host that is not here is its own. */
  sshHosts: Record<string, string> = {};
  /** The hosts `sshHost` was asked about. */
  sshAsked: string[] = [];
  private progress: ((line: string) => void) | undefined;

  async sshHost(host: string) {
    this.sshAsked.push(host);
    return this.sshHosts[host] ?? host;
  }

  /** Plays a line of stderr of the clone that is running, as git writes it. */
  emitProgress(...lines: string[]) {
    for (const line of lines) this.progress?.(line);
  }

  async run(folder: string, args: string[], options?: { timeoutMs?: number; env?: NodeJS.ProcessEnv; signal?: AbortSignal; onProgress?: (line: string) => void }): Promise<GitResult> {
    this.calls.push({ folder, args, timeoutMs: options?.timeoutMs, env: options?.env });
    if (args[0] === 'clone') {
      this.progress = options?.onProgress;
      // clone -- <url> <dest>: git makes the folder first; a failure or an abort leaves it half made
      const [url, dest] = args.slice(2) as [string, string];
      mkdirSync(dest, { recursive: true });
      const signal = options?.signal;
      if (this.clonePending !== undefined) await Promise.race([this.clonePending, new Promise((resolve) => signal?.addEventListener('abort', resolve, { once: true }))]);
      if (signal?.aborted === true) return { ok: false, code: null, aborted: true, stderr: 'killed' };
      const failure = this.failures.get(args.join(' '));
      if (failure !== undefined) return failure;
      mkdirSync(join(dest, '.git'));
      this.repos.set(dest, { head: 'main', branches: ['main'], ...structuredClone(this.cloned), origin: url });
      return { ok: true, out: '' };
    }
    if (args[0] === 'init') {
      // init -b <branch>: a failure leaves a half-made .git, as git can
      mkdirSync(join(folder, '.git'), { recursive: true });
      const failure = this.failures.get(args.join(' '));
      if (failure !== undefined) return failure;
      this.repos.set(folder, { head: args[2]!, branches: [] });
      return { ok: true, out: '' };
    }
    const failure = this.failures.get(args.join(' '));
    if (failure !== undefined) return failure;
    const repo = this.repos.get(folder);
    if (repo === undefined) return { ok: false, code: 128, stderr: 'fatal: not a git repository' };
    const out = (...printed: string[]) => ({ ok: true as const, out: printed.map((line) => `${line}\n`).join('') });
    const no = { ok: false as const, code: 1, stderr: '' };
    const [verb, ...rest] = args[0] === '--no-optional-locks' ? args.slice(1) : args;
    if (verb === 'rev-parse' && rest.includes('--verify')) return [...repo.branches.map((name) => `refs/heads/${name}`), ...(repo.remoteBranches ?? []).map((name) => `refs/remotes/origin/${name}`)].includes(rest.at(-1)!) ? out(rest.at(-1)!) : no;
    if (verb === 'worktree' && rest[0] === 'add') {
      const signal = options?.signal;
      if (this.worktreePending !== undefined) await Promise.race([this.worktreePending, new Promise((resolve) => signal?.addEventListener('abort', resolve, { once: true }))]);
      if (signal?.aborted === true) return { ok: false, code: null, aborted: true, stderr: 'killed' };
      if (rest.length === 3) {
        // worktree add <path> <branch>: an existing branch checked out again in a new folder
        const [, again, existing] = rest;
        if (repo.branches.includes(existing!) === false) return { ok: false, code: 128, stderr: 'fatal: invalid reference' };
        mkdirSync(again!, { recursive: true });
        (repo.worktrees ??= []).push({ path: again!, branch: existing! });
        return out();
      }
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
    if (verb === 'remote' && rest[0] === 'get-url') return repo.origin === undefined ? { ok: false as const, code: 2, stderr: '' } : out(repo.origin);
    if (verb === 'config') return repo.origin === undefined ? no : out(repo.origin);
    if (verb === 'symbolic-ref' && rest.includes('refs/remotes/origin/HEAD')) return repo.originHead === undefined ? no : out(`refs/remotes/origin/${repo.originHead}`);
    if (verb === 'symbolic-ref') return repo.head === null ? no : out(repo.head);
    if (verb === 'for-each-ref') {
      const apart = (name: string) => (repo.ahead?.[name] ?? 0) + (repo.behind?.[name] ?? 0) > 0;
      return out(...repo.branches.map((name) => `refs/heads/${name} ${apart(name) ? 'local' : 'same'}-${name}`), ...(repo.remoteBranches ?? []).map((name) => `refs/remotes/origin/${name} ${apart(name) ? 'remote' : 'same'}-${name}`), ...(repo.originHead === undefined ? [] : ['refs/remotes/origin/HEAD same-HEAD']));
    }
    if (verb === 'rev-list' && rest.includes('--left-right')) {
      const name = rest.at(-1)!.split('...')[0]!.replace('refs/heads/', '');
      return { ok: true as const, out: `${repo.ahead?.[name] ?? 0}\t${repo.behind?.[name] ?? 0}\n` };
    }
    if (verb === 'rev-list' && rest[1]!.includes('..')) return out(String(repo.behind?.[rest[1]!.split('..')[0]!.replace('refs/heads/', '')] ?? 0));
    if (verb === 'rev-list') return out(String(repo.unpushed?.[rest[1]!.replace('refs/heads/', '')] ?? 0));
    if (verb === 'switch') {
      // switch <branch>, or switch --track origin/<branch>, which makes the local branch
      const target = rest.at(-1)!;
      const local = target.replace(/^origin\//, '');
      if (rest[0] === '--track') repo.branches.push(local);
      else if (repo.branches.includes(target) === false) return { ok: false, code: 128, stderr: 'fatal: invalid reference' };
      repo.head = local;
      return out();
    }
    if (verb === 'fetch') return out();
    if (verb === 'status') return out(...(repo.status ?? []));
    return { ok: false, code: 129, stderr: `the fake git does not know ${verb}` };
  }
}

/** What brings repositories onto the Mac, over a fake git and a fake `gh`: the token is `ghp_fake`, GitHub lists nothing and knows `main` and `feat/x` for any repository. */
export const fakeProjects = (git: Git, clock = new FakeClock(), github: Partial<GithubRepos> = {}) =>
  createProjects({ git, clock, token: async () => 'ghp_fake', github: { repos: async () => ({ repos: [], hasMore: false }), login: async () => 'me', branches: async () => ({ default: 'main', branches: ['main', 'feat/x'], hasMore: false }), ...github } });

/** A `Shell` that runs nothing: it records each command and ends as `results` says (ok by default), after playing the `lines` it has for the command as progress. */
export class FakeShell implements Shell {
  /** Every command run, in order, with the folder and the environment it was given. */
  calls: { folder: string; command: string; env: NodeJS.ProcessEnv }[] = [];
  /** How a command ends, by the command: not here, it succeeds. */
  results = new Map<string, Extract<ShellResult, { ok: false }>>();
  /** The lines a command writes before it ends, by the command. */
  lines = new Map<string, string[]>();
  /** While set, a command waits for it (or for its signal to abort) before it ends: a command that is still running. */
  pending: Promise<void> | undefined;

  async run(folder: string, command: string, { env, signal, onProgress }: Parameters<Shell['run']>[2]): Promise<ShellResult> {
    this.calls.push({ folder, command, env });
    for (const line of this.lines.get(command) ?? []) onProgress(line);
    if (this.pending !== undefined) await Promise.race([this.pending, new Promise((resolve) => signal.addEventListener('abort', resolve, { once: true }))]);
    if (signal.aborted) return { ok: false, code: null, aborted: true, output: '' };
    return this.results.get(command) ?? { ok: true };
  }
}
