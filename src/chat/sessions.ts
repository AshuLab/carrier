import { accessSync, constants } from 'node:fs';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { and, asc, count, desc, eq, gt, inArray, isNotNull, isNull, lt, ne, sql } from 'drizzle-orm';
import { createScopedLogger } from '@ashulab/universal-logger';
import { carrierHome } from '../config/default-path.ts';
import { type ChatAgents, chatAccount, readAccounts } from './account.ts';
import type { ChatAgent, ChatSettings } from './config.ts';
import { resolveBinary } from '../harnesses/common.ts';
import type { Clock } from '../orchestration/clock.ts';
import type { ChatDb } from './db.ts';
import { checkFolder } from './folder.ts';
import { buildHandoff } from './handoff.ts';
import { realMachine, type Machine } from '../doctor/detect.ts';
import { createHealth, realProbes, type HealthProbes } from './health.ts';
import { childOptions, isScaleHarness, type Level, levelOf } from './levels.ts';
import type { McpSessionRegistry } from './mcp.ts';
import { createProviders } from './providers.ts';
import type { Git } from './git.ts';
import type { Plan, Step, StepEvent } from './plan.ts';
import { ChatRefused, type ChatChoice, type ChatCommand, type ChatConversation, type ChatEvent, type ChatOption, type ChatQuestion, type ChatRunner } from './runner.ts';
import { chatEvents, chatTurns, sessions } from './schema.ts';
import { boundEvent, chatCaps, previewOf, titleOf } from './transcript.ts';
import { checkName, suggestName } from './names.ts';
import { createProject, projectFolder, type createProjects } from './projects.ts';
import { createWorktree, deleteWorktree, previewWorktree, removeWorktree } from './worktree.ts';
import { checkout, fetchFolder, inspectFolder } from './workspace.ts';

const log = createScopedLogger('chat');

export const IDLE_CLOSE_MS = 60_000;
/** The children of one session that may work or wait for an approval at the same time ([ADR 0033](../../docs/adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md)). */
const MAX_RUNNING_CHILDREN = 4;

const DAY = 86_400_000;
/** The lifecycle's ages (ADR 0019), as `chat.json` gives them. */
export type SessionAges = Pick<ChatSettings, 'archiveAfterDays' | 'deleteAfterDays'>;
const idleFor = (row: { state: State; lastActiveAt: number }, live: boolean, now: number, days: number | 'never') => days !== 'never' && row.state === 'idle' && !live && now - row.lastActiveAt >= days * DAY;

type Harness = (typeof sessions.$inferSelect)['harness'];
type State = (typeof sessions.$inferSelect)['state'];

/** Where a session works: the folder it was opened in, or a worktree made for it from that base folder. */
export type SessionWorkspace = { kind: 'folder' } | { kind: 'worktree'; branch: string; from: string; base: string; path: string };

/** A child session as its parent's summary lists it; `level` is the permission level it runs at, and `needsPerson` says that it waits for an approval or a question. */
export type ChildSummary = { id: string; agent: string; harness: Harness; state: State; level: Level | null; needsPerson: boolean };

export type SessionSummary = Omit<typeof sessions.$inferSelect, 'keptAt' | 'options' | 'pid' | 'pgid' | 'command' | 'plan' | 'workspaceKind' | 'worktreeBranch' | 'worktreeFrom' | 'worktreeBase' | 'worktreePath' | 'delegationRequestId'> & {
  workspace: SessionWorkspace;
  /** The sessions that this one started by delegating, oldest first. */
  children: ChildSummary[];
  /** `running` while the host prepares the session, `failed` when a step failed and the plan is kept, null otherwise. */
  preparation: 'running' | 'failed' | null;
};

export type PendingApproval = { approvalId: string; tool: string; arg?: string; choices: ChatChoice[]; questions?: ChatQuestion[] };

/** A session whose agent process runs: what is only true while it does. */
type Live = {
  conversation: ChatConversation;
  state: State;
  /** The text of the message being written, not stored until it ends. */
  streaming: string;
  /** The approvals asked and not yet answered, as they are stored (redacted and bounded). */
  approvals: Map<string, PendingApproval>;
  turn?: { startedAt: number; toolCalls: number };
  /** True while the `message` step of a preparation waits for the agent's first answer. */
  awaitingAnswer?: boolean;
  cancelIdle?: () => void;
  /** The invocation its MCP token was issued for. */
  invocationId: string;
  /** Set when a switch of agent replaced this conversation: its events are no longer recorded. */
  detached?: boolean;
};

export type ChatSessionsDeps = {
  db: ChatDb;
  /** The agents a chat can start with, in the order `chat.json` lists them, or the accounts of `providers.json`. */
  agents: ChatAgents;
  clock: Clock;
  /** The runner of each harness; a harness with none cannot be opened. */
  runners: Partial<Record<Harness, ChatRunner>>;
  env: NodeJS.ProcessEnv;
  /** The `git` of the machine. */
  git: Git;
  /** What brings a repository onto the Mac, for a plan that clones one. */
  projects: Pick<ReturnType<typeof createProjects>, 'cloneRepo' | 'repoFolder' | 'stepOf'>;
  /** Whether an agent's binary is there. */
  binaryFound: (command: string) => boolean;
  /** What the `health` request runs; the machine's own tools unless a test replaces it. */
  probes?: HealthProbes;
  /** What the `providers` request asks of the machine; the real one unless a test replaces it. */
  machine?: Machine;
  /** The lifecycle's ages now: `list` says from them when the clock will delete each archived session. */
  ages: () => SessionAges;
  /** Called when a session becomes or stops being live, so the host can start or cancel its own countdown. */
  onLiveChange: () => void;
  /** The chat MCP: the registry that issues each conversation's token and the URL of the endpoint, which is undefined when the host could not start it. Without this a host has no MCP and says nothing of it. */
  mcp?: { registry: McpSessionRegistry; url: () => string | undefined };
};

/** The key the chat MCP is registered under in each harness, so it cannot collide with a server the person configured. */
const MCP_SERVER_NAME = 'carrier-chat';

/** Refuses, naming the option, one the provider does not list or a value it does not offer for it. */
function checkOption(options: ChatOption[], id: string, value: string) {
  const option = options.find((candidate) => candidate.id === id);
  if (option === undefined) throw new ChatRefused(`This agent has no option "${id}"; it offers: ${options.map((o) => o.id).join(', ') || 'none'}`);
  if (option.values.some((offered) => offered.id === value) === false) throw new ChatRefused(`"${value}" is not a value of the option "${id}"; it offers: ${option.values.map((v) => v.id).join(', ')}`);
}

export function binaryFound(command: string): boolean {
  try {
    if (command.includes('/')) accessSync(command, constants.X_OK);
    else resolveBinary(command);
    return true;
  } catch {
    return false;
  }
}

/** The sessions of the chat host: what the socket's requests do, over `chat.db` and the runners. */
export function createSessions({ db, agents, clock, runners, env, git, projects, binaryFound, probes = realProbes, machine = realMachine, ages, onLiveChange, mcp }: ChatSessionsDeps) {
  const listed = () => (typeof agents === 'function' ? agents() : agents);
  const health = createHealth({ agents, clock, binaryFound, probes });
  const providers = createProviders({ clock, machine, binaryFound });
  const lives = new Map<string, Live>();
  /** Set by closeAll, the host's shutdown: a clock pass in flight leaves the sessions it has not reached alone. */
  let closed = false;
  // Sessions being deleted: no agent may open in their folder while it is removed.
  const deleting = new Set<string>();
  // Sessions switching agent: a marker of its own, so nothing that touches the session runs while the new conversation opens and the old one ends.
  const switching = new Set<string>();
  const notSwitching = (sessionId: string) => {
    if (switching.has(sessionId)) throw new ChatRefused('This session is switching to another agent; try again in a moment');
  };
  let clients = 0;

  const exists = (sessionId: string) => db.select({ id: sessions.id }).from(sessions).where(eq(sessions.id, sessionId)).get() !== undefined;
  const row = (sessionId: string) => {
    const found = db.select().from(sessions).where(eq(sessions.id, sessionId)).get();
    if (found === undefined) throw new ChatRefused('There is no such session');
    return found;
  };
  /** Refuses, in words, a request that treats a child as a conversation of the person's: it belongs to its parent session (ADR 0033). An unknown session is refused as `row` does. */
  const refuseChild = (sessionId: string, verb: string) => {
    if (row(sessionId).parentSessionId !== null) throw new ChatRefused(`This session belongs to its parent session and cannot be ${verb}`);
  };
  /** The options a session has now: its live conversation's, else the ones stored. */
  const optionsOf = (sessionId: string, stored: Record<string, string> | null) => {
    const live = lives.get(sessionId);
    return live === undefined ? (stored ?? {}) : Object.fromEntries(live.conversation.options.map((option) => [option.id, option.current]));
  };
  const childrenOf = (parentId: string): ChildSummary[] =>
    db.select().from(sessions).where(eq(sessions.parentSessionId, parentId)).orderBy(asc(sessions.createdAt)).all().map((child) => ({
      id: child.id,
      agent: child.agent,
      harness: child.harness,
      state: child.state,
      level: isScaleHarness(child.harness) ? (levelOf(child.harness, optionsOf(child.id, child.options)) ?? null) : null,
      needsPerson: child.state === 'waiting_approval',
    }));
  const summary = ({ keptAt: _keptAt, options: _options, pid: _pid, pgid: _pgid, command: _command, delegationRequestId: _delegationRequestId, plan, workspaceKind, worktreeBranch, worktreeFrom, worktreeBase, worktreePath, ...rest }: typeof sessions.$inferSelect): SessionSummary => ({
    ...rest,
    children: childrenOf(rest.id),
    preparation: rest.state === 'preparing' ? 'running' : plan === null ? null : 'failed',
    workspace: workspaceKind === 'worktree' ? { kind: 'worktree', branch: worktreeBranch!, from: worktreeFrom!, base: worktreeBase!, path: worktreePath! } : { kind: 'folder' },
  });

  /** What a list says of how a session went: the words its agent last wrote (one line, already redacted as stored), the turns that finished and the model of the last. */
  const activity = (sessionId: string) => {
    const message = db.select({ data: chatEvents.data }).from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'assistant'))).orderBy(desc(chatEvents.id)).limit(1).get();
    const turns = db.select({ n: count() }).from(chatTurns).where(eq(chatTurns.sessionId, sessionId)).get()?.n ?? 0;
    const last = db.select({ model: chatTurns.model }).from(chatTurns).where(eq(chatTurns.sessionId, sessionId)).orderBy(desc(chatTurns.id)).limit(1).get();
    const text = message?.data.text;
    return { lastMessage: typeof text === 'string' && text.trim() !== '' ? previewOf(text) : null, turns, model: last?.model ?? null };
  };

  // Worktrees are made one at a time: what a request checked (a free name) is still true when git adds.
  let making: Promise<unknown> = Promise.resolve();
  const exclusive = <T>(work: () => Promise<T>): Promise<T> => {
    const run = making.then(work, work);
    making = run.catch(() => {});
    return run;
  };

  // An idle session with no client attached is closed after a minute; working or waiting ones are kept.
  const armIdle = (sessionId: string, live: Live) => {
    live.cancelIdle?.();
    live.cancelIdle = live.state === 'idle' && clients === 0 && !switching.has(sessionId) ? clock.after(IDLE_CLOSE_MS, async () => void (await close({ sessionId }))) : undefined;
  };
  const touch = (sessionId: string, live: Live, state: State = live.state) => {
    live.state = state;
    db.update(sessions).set({ state, lastActiveAt: clock.now(), ...(live.conversation.nativeId !== undefined && { nativeId: live.conversation.nativeId }) }).where(eq(sessions.id, sessionId)).run();
    armIdle(sessionId, live);
  };
  const store = (sessionId: string, event: ChatEvent | StepEvent) => {
    const data = boundEvent(event);
    if (data !== undefined) db.insert(chatEvents).values({ sessionId, at: clock.now(), kind: event.kind, data }).run();
  };

  // Sessions whose steps run in the background and are not live yet: the host is not idle while one does. `abort` stops the running step, `done` ends when the steps stopped.
  const preparing = new Map<string, { abort: AbortController; done: Promise<void> }>();
  // The latest line of git's progress for the clone of a session that is cloning: shown by `events`, never stored.
  const progress = new Map<string, string>();
  const stepEvent = (sessionId: string, step: Step, status: StepEvent['status'], detail?: string) => store(sessionId, { kind: 'step', step, status, ...(detail !== undefined && { detail }) });
  /** How the last event of a step left it, undefined when the step never ran. */
  const lastStatus = (sessionId: string, step: Step) => {
    const events = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'step'))).orderBy(desc(chatEvents.id)).all();
    return events.find((event) => event.data.step === step)?.data.status as StepEvent['status'] | undefined;
  };
  /** Stops a preparation at a step: the session is idle, the plan stays and the event says why. */
  const failStep = (sessionId: string, step: Step, detail: string) => {
    stepEvent(sessionId, step, 'failed', detail);
    db.update(sessions).set({ state: 'idle', lastActiveAt: clock.now() }).where(eq(sessions.id, sessionId)).run();
  };
  // A host that stopped mid-preparation left sessions whose last step is still running: it comes back failed as interrupted.
  for (const { id: sessionId } of db.select({ id: sessions.id }).from(sessions).where(isNotNull(sessions.plan)).all()) {
    const last = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'step'))).orderBy(desc(chatEvents.id)).limit(1).get();
    if (last?.data.status === 'running') stepEvent(sessionId, last.data.step as Step, 'failed', 'Carrier stopped while this step was running');
    db.update(sessions).set({ state: 'idle' }).where(and(eq(sessions.id, sessionId), eq(sessions.state, 'preparing'))).run();
  }

  const onEvent = (sessionId: string, live: Live, event: ChatEvent) => {
    // The first thing the agent does after the first message ends the `message` step: an answer, or an error that fails it.
    if (live.awaitingAnswer === true && event.kind !== 'option') {
      live.awaitingAnswer = false;
      if (event.kind === 'error' || (event.kind === 'turn_end' && event.outcome === 'error')) {
        store(sessionId, event);
        failStep(sessionId, 'message', 'The agent ended with an error before it answered');
        live.turn = undefined;
        live.state = 'idle';
        close({ sessionId }).catch((error) => log.error('closing an agent that failed its first answer failed', error));
        return;
      }
      stepEvent(sessionId, 'message', 'done');
      db.update(sessions).set({ plan: null }).where(eq(sessions.id, sessionId)).run();
      touch(sessionId, live, 'working');
    }
    if (event.kind === 'delta') return void (live.streaming += event.text);
    if (event.kind === 'turn_end' && live.turn === undefined) return; // a turn already recorded (an interrupt, then the adapter's own end)
    if (event.kind === 'assistant' || event.kind === 'turn_end') live.streaming = '';
    store(sessionId, event);
    if (event.kind === 'approval') live.approvals.set(event.approvalId, boundEvent(event) as PendingApproval);
    if (event.kind === 'approval_answered') live.approvals.delete(event.approvalId);
    if (event.kind === 'turn_end') live.approvals.clear(); // an interrupted turn drops what it was waiting for
    if (event.kind === 'option') {
      const { options } = row(sessionId);
      db.update(sessions).set({ options: { ...options, [event.id]: event.value } }).where(eq(sessions.id, sessionId)).run();
    }
    if (event.kind === 'tool_start' && live.turn) live.turn.toolCalls++;
    if (event.kind === 'turn_end') {
      const startedAt = live.turn?.startedAt ?? clock.now();
      const { harness, agent } = row(sessionId);
      db.insert(chatTurns).values({ sessionId, startedAt, harness, agent, nativeId: live.conversation.nativeId ?? null, model: event.model ?? null, outcome: event.outcome, durationMs: clock.now() - startedAt, toolCalls: live.turn?.toolCalls ?? 0, usage: event.usage ?? null }).run();
      live.turn = undefined;
    }
    touch(sessionId, live, event.kind === 'approval' ? 'waiting_approval' : event.kind === 'turn_end' ? 'idle' : event.kind === 'approval_answered' ? 'working' : live.state);
  };

  /** The agents that were told to end and have not yet: a close that does not wait leaves them here, and the host's stop waits for them. */
  const ending = new Set<Promise<void>>();

  /** Closes a live session: it is no longer live as soon as this runs, and the agent's end (SIGTERM, then SIGKILL) is waited for unless `wait` is false. */
  async function close({ sessionId }: { sessionId: string }, { wait = true }: { wait?: boolean } = {}) {
    row(sessionId);
    const live = lives.get(sessionId);
    if (live === undefined) return {};
    lives.delete(sessionId);
    revoke(live.invocationId);
    live.cancelIdle?.();
    db.update(sessions).set({ state: 'idle', pid: null, pgid: null, command: null }).where(eq(sessions.id, sessionId)).run();
    const failed = (error: unknown) => log.error('closing a conversation failed', error);
    if (wait) {
      try {
        await live.conversation.close();
      } catch (error) {
        failed(error);
      }
    } else {
      const ended = live.conversation.close().catch(failed);
      ending.add(ended);
      void ended.then(() => ending.delete(ended));
    }
    onLiveChange();
    return {};
  }

  /** Readies a session to be archived or deleted: refuses an unknown one, and one working or waiting for an approval; closes an idle live one.
   * An archive does not wait for the agent to end, which can take seconds (the person is watching the row go); a delete does, as its worktree cannot be removed under a running agent. */
  async function settle(sessionId: string, verb: 'archive' | 'delete') {
    notSwitching(sessionId);
    if (row(sessionId).state === 'preparing') throw new ChatRefused(`This session is being prepared; wait for it to finish, then ${verb} it`);
    const live = lives.get(sessionId);
    if (live === undefined) return;
    if (live.state !== 'idle') throw new ChatRefused(`This session is ${live.state === 'working' ? 'working' : 'waiting for an approval'}; interrupt or close it first, then ${verb} it`);
    await close({ sessionId }, { wait: verb === 'delete' });
    if (lives.has(sessionId)) throw new ChatRefused('This session was resumed meanwhile; close it first'); // a resume that finished during the close
  }

  /** How an agent starts, from its account as `providers.json` has it now: refuses, naming the account, one that is missing or Antigravity's. */
  const launchOf = (chosen: ChatAgent) => {
    const { harness, command, launch, env: accountEnv } = chatAccount(readAccounts(), chosen, env);
    const runner = runners[harness];
    if (runner === undefined) throw new ChatRefused(`This host has no chat runner for ${harness}`);
    return { chosen, harness, runner, command, launch, env: accountEnv };
  };
  type Launch = ReturnType<typeof launchOf>;

  /** A fresh invocation for one conversation of a real session, with the MCP to hand its runner: none when the host has no endpoint. */
  const issueMcp = (sessionId: string) => {
    const invocationId = randomUUID();
    const url = mcp?.url();
    if (mcp === undefined || url === undefined) return { invocationId, args: undefined };
    return { invocationId, args: { serverName: MCP_SERVER_NAME, url, token: mcp.registry.issue({ sessionId, invocationId, capabilities: ['read'] }) } };
  };
  const revoke = (invocationId: string) => mcp?.registry.revokeByInvocation(invocationId);

  async function openConversation({ chosen, runner, command, launch, env }: Launch, args: { folder: string; options: Record<string, string>; resume?: string; child?: boolean; mcp?: { serverName: string; url: string; token: string }; instructions?: string }) {
    try {
      return await runner.open({ ...args, command, launch, env });
    } catch (error) {
      if (error instanceof ChatRefused) throw error;
      log.error('a chat runner failed to open', error);
      throw new ChatRefused(`${chosen.name} could not be started`);
    }
  }

  /** Removes the session with all its events and turns. A live idle session is closed first; a working or waiting one is refused. */
  async function deleteSession({ sessionId }: { sessionId: string }) {
    // marked before the first await, so a resume that comes in meanwhile is refused
    deleting.add(sessionId);
    try {
      await settle(sessionId, 'delete');
      const { workspaceKind, worktreeBranch, worktreeFrom, worktreeBase, worktreePath } = row(sessionId);
      // The worktree goes first: one that cannot be removed stops the deletion and the session stays.
      if (workspaceKind === 'worktree') await deleteWorktree(git, { path: worktreePath!, branch: worktreeBranch!, from: worktreeFrom!, base: worktreeBase! });
      db.transaction((tx) => {
        tx.delete(chatEvents).where(eq(chatEvents.sessionId, sessionId)).run();
        tx.delete(chatTurns).where(eq(chatTurns.sessionId, sessionId)).run();
        tx.delete(sessions).where(eq(sessions.id, sessionId)).run();
      });
    } finally {
      deleting.delete(sessionId);
    }
    return {};
  }

  /** Records a message, starts its turn and hands it to the agent: the person's through `send`, and a child's first one, its task, from the host itself. */
  const deliver = (sessionId: string, live: Live, shown: string, text: string, invoked?: ChatCommand) => {
    live.turn = { startedAt: clock.now(), toolCalls: 0 };
    store(sessionId, { kind: 'user', text: shown, ...(invoked !== undefined && { command: invoked.name }) });
    touch(sessionId, live, 'working');
    try {
      live.conversation.send(text, invoked);
    } catch (error) {
      log.error('a message could not be sent to the agent', error);
      live.turn = undefined;
      touch(sessionId, live, 'idle');
      throw new ChatRefused('The message could not be delivered to the agent');
    }
  };

  /** Makes a conversation the live one of a session. */
  const recordProcess = (sessionId: string, conversation: ChatConversation) => {
    const { pid = null, pgid = null, command = null } = conversation.process ?? {};
    db.update(sessions).set({ pid, pgid, command }).where(eq(sessions.id, sessionId)).run();
  };
  const attach = (sessionId: string, conversation: ChatConversation, invocationId: string, state: State = 'idle', { record = true }: { record?: boolean } = {}) => {
    const live: Live = { conversation, state, streaming: '', approvals: new Map(), invocationId };
    lives.set(sessionId, live);
    if (record) recordProcess(sessionId, conversation);
    conversation.onEvent((event) => {
      if (live.detached === true) return;
      try {
        onEvent(sessionId, live, event);
      } catch (error) {
        log.error('a chat event could not be handled', error);
      }
    });
    // An agent that ends on its own ends the turn that was running (error) and then the live session, as a close does.
    conversation.onEnd(() => {
      if (lives.get(sessionId) !== live) return;
      try {
        if (live.turn !== undefined) onEvent(sessionId, live, { kind: 'turn_end', outcome: 'error' }); // the adapter normally said so already
      } catch (error) {
        log.error('the end of a turn could not be recorded', error);
      }
      close({ sessionId }).catch((error) => log.error('dropping a session whose agent ended failed', error));
    });
    // A conversation without the MCP stays usable; the person is told.
    if (mcp !== undefined && (mcp.url() === undefined || conversation.mcpProblem !== undefined)) {
      store(sessionId, { kind: 'notice', text: conversation.mcpProblem === undefined ? "Carrier's own tools are not available in this session: the host could not start them." : `The agent could not use Carrier's own tools (${conversation.mcpProblem}), so it works without them.` });
    }
    armIdle(sessionId, live);
    onLiveChange();
    return live;
  };

  /** The name the repository lists for the branch the plan picked. A repository the plan cloned lists its other branches as `origin/<name>`, while the draft read them from GitHub as plain names. */
  const listedAs = async (folder: string, { workspace }: Plan, branch: string) => {
    if (workspace.kind !== 'repo') return branch;
    const { branches } = await inspectFolder(git, folder);
    return branches.some((listed) => listed.name === branch) ? branch : `origin/${branch}`;
  };

  /**
   * The `worktree` or `checkout` step of a plan, when it has one: the folder the agent runs in, or undefined once the step failed and was recorded.
   * A worktree already recorded on the session is the one made before, so it is reused and not made twice; so is a checkout already done.
   */
  async function arrange(sessionId: string, folder: string, plan: Plan, signal: AbortSignal): Promise<string | undefined> {
    const { worktree, branch } = plan;
    if (worktree === undefined && branch === undefined) return folder;
    const step = worktree === undefined ? 'checkout' : 'worktree';
    const recorded = row(sessionId);
    if (recorded.workspaceKind === 'worktree') return recorded.worktreePath!;
    if (step === 'checkout' && lastStatus(sessionId, step) === 'done') return folder; // a retry does not switch the branch again
    stepEvent(sessionId, step, 'running');
    try {
      if (worktree !== undefined) {
        if (branch === undefined) throw new ChatRefused('A worktree needs the branch it starts from');
        // an empty name is the host's to generate
        const made = await exclusive(async () => createWorktree(git, folder, { from: await listedAs(folder, plan, branch), ...(worktree.name !== undefined && worktree.name !== '' && { name: worktree.name }) }, signal));
        db.update(sessions).set({ folder: made.path, workspaceKind: 'worktree', worktreeBranch: made.branch, worktreeFrom: made.from, worktreeBase: made.base, worktreePath: made.path }).where(eq(sessions.id, sessionId)).run();
        stepEvent(sessionId, step, 'done');
        return made.path;
      }
      await checkout(git, folder, await listedAs(folder, plan, branch!));
      stepEvent(sessionId, step, 'done');
      return folder;
    } catch (error) {
      if (error instanceof ChatRefused === false) log.error(`preparing a session failed at ${step}`, error);
      failStep(sessionId, step, error instanceof ChatRefused ? error.message : `The ${step} could not be done`);
    }
  }

  /** The `project` step of a plan: makes the folder with `git init` and records it as the session's. False once the step failed and was recorded. A project already made by an earlier try is reused. */
  async function makeProject(sessionId: string, name: string): Promise<boolean> {
    if (lastStatus(sessionId, 'project') === 'done') return true;
    stepEvent(sessionId, 'project', 'running');
    try {
      const { folder } = await createProject(git, name);
      db.update(sessions).set({ folder }).where(eq(sessions.id, sessionId)).run();
      stepEvent(sessionId, 'project', 'done');
      return true;
    } catch (error) {
      if (error instanceof ChatRefused === false) log.error('preparing a session failed at project', error);
      failStep(sessionId, 'project', error instanceof ChatRefused ? error.message : 'The project could not be made');
      return false;
    }
  }

  /** The `clone` step of a plan for a repository, or `fetch` when it is already in the projects folder. False once the step failed and was recorded. A clone or a fetch already done by an earlier try is reused. */
  async function bring(sessionId: string, repo: string, signal: AbortSignal): Promise<boolean> {
    if (lastStatus(sessionId, 'clone') === 'done' || lastStatus(sessionId, 'fetch') === 'done') return true;
    const step = projects.stepOf(repo);
    stepEvent(sessionId, step, 'running');
    try {
      await projects.cloneRepo({ repo }, signal, (line) => void progress.set(sessionId, line));
      stepEvent(sessionId, step, 'done');
      return true;
    } catch (error) {
      if (error instanceof ChatRefused === false) log.error(`preparing a session failed at ${step}`, error);
      failStep(sessionId, step, error instanceof ChatRefused ? error.message : `The ${step} could not be done`);
      return false;
    } finally {
      progress.delete(sessionId);
    }
  }

  /** The steps of a plan, in the background: it never throws, a failure is recorded as a step that failed. */
  async function prepare(sessionId: string, launch: Launch, base: string, plan: Plan, signal: AbortSignal) {
    try {
      if (plan.workspace.kind === 'project' && (await makeProject(sessionId, plan.workspace.name)) === false) return;
      if (plan.workspace.kind === 'repo' && (await bring(sessionId, plan.workspace.repo, signal)) === false) return;
      const folder = await arrange(sessionId, plan.workspace.kind === 'project' ? row(sessionId).folder : base, plan, signal);
      if (folder === undefined || signal.aborted) return;
      stepEvent(sessionId, 'agent', 'running');
      const { chosen } = launch;
      const options = { ...(chosen.model && { model: chosen.model }), ...chosen.options, ...plan.options };
      let conversation: ChatConversation | undefined;
      const issued = issueMcp(sessionId);
      try {
        conversation = await openConversation(launch, { folder, options, mcp: issued.args });
        for (const [id, value] of Object.entries(options)) checkOption(conversation.options, id, value);
      } catch (error) {
        revoke(issued.invocationId);
        await conversation?.close().catch((closing) => log.error('closing a refused conversation failed', closing));
        if (error instanceof ChatRefused === false) log.error('preparing a session failed at the agent', error);
        return failStep(sessionId, 'agent', error instanceof ChatRefused ? error.message : 'The agent could not be started');
      }
      if (signal.aborted) {
        revoke(issued.invocationId);
        return void (await conversation.close().catch((closing) => log.error('closing the agent of a cancelled preparation failed', closing)));
      }
      stepEvent(sessionId, 'agent', 'done');
      const live = attach(sessionId, conversation, issued.invocationId, 'preparing');
      stepEvent(sessionId, 'message', 'running');
      live.awaitingAnswer = true;
      live.turn = { startedAt: clock.now(), toolCalls: 0 };
      // a retry sends the same message again, which the conversation already shows
      if (db.select({ id: chatEvents.id }).from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'user'))).limit(1).get() === undefined) store(sessionId, { kind: 'user', text: plan.text });
      try {
        conversation.send(plan.text);
      } catch (error) {
        log.error('the first message could not be sent to the agent', error);
        live.awaitingAnswer = false;
        live.turn = undefined;
        live.state = 'idle';
        failStep(sessionId, 'message', 'The message could not be delivered to the agent');
        await close({ sessionId });
      }
    } catch (error) {
      log.error('preparing a session failed', error);
    } finally {
      preparing.delete(sessionId);
      onLiveChange();
    }
  }

  /** What a plan needs to run, refusing in words one that cannot. A project's or a repository's folder is the one it will be made or cloned at. */
  const targetOf = (plan: Plan) => {
    const chosen = listed().find((candidate) => candidate.name === plan.agent);
    if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${plan.agent}"`);
    return { launch: launchOf(chosen), folder: plan.workspace.kind === 'project' ? projectFolder(plan.workspace.name) : plan.workspace.kind === 'repo' ? projects.repoFolder(plan.workspace.repo) : checkFolder(plan.workspace.folder, carrierHome()) };
  };
  /** Runs the steps of a plan in the background. */
  const begin = (sessionId: string, { launch, folder }: ReturnType<typeof targetOf>, plan: Plan) => {
    const running = { abort: new AbortController(), done: Promise.resolve() };
    preparing.set(sessionId, running);
    running.done = prepare(sessionId, launch, folder, plan, running.abort.signal);
  };

  /** What each agent offered when it was last asked (a draft lists the models before a session exists), kept ten minutes. */
  const offered = new Map<string, { at: number; offer: Promise<{ options: ChatOption[]; commands: ChatCommand[] }> }>();

  /**
   * The options and the commands an agent offers, with the values it would start with, before any session exists: it starts the agent in a folder of
   * nobody's, reads what it lists and ends it. Kept ten minutes, and a failure is not kept.
   */
  const offerOf = async ({ agent }: { agent: string }) => {
    const chosen = listed().find((candidate) => candidate.name === agent);
    if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${agent}"`);
    const launch = launchOf(chosen);
    const known = offered.get(agent);
    if (known !== undefined && clock.now() - known.at < 10 * 60_000) return await known.offer;
    const offer = (async () => {
      const conversation = await openConversation(launch, { folder: tmpdir(), options: { ...(chosen.model && { model: chosen.model }), ...chosen.options } });
      try {
        return { options: [...conversation.options], commands: [...conversation.commands] };
      } finally {
        await conversation.close().catch((error) => log.error('closing the agent that listed its options failed', error));
      }
    })();
    offered.set(agent, { at: clock.now(), offer });
    try {
      return await offer;
    } catch (error) {
      offered.delete(agent);
      throw error;
    }
  };

  /** Refuses in words a model that the agent's harness does not list: both harnesses accept an unknown one when they open and fail on the first turn, so the check is against the option probe's list. */
  const checkModel = async (agent: string, model: string) => {
    const listedModels = await offerOf({ agent }).then(
      ({ options }) => options.find((option) => option.id === 'model')?.values.map((value) => value.id),
      (error) => {
        log.error(`listing the models of the agent ${agent} failed`, error);
        throw new ChatRefused(`The models of the agent "${agent}" could not be listed, so "${model}" cannot be checked`);
      },
    );
    if (listedModels?.includes(model) !== true) throw new ChatRefused(`"${model}" is not a model of the agent "${agent}"; it lists: ${listedModels?.join(', ') || 'none'}`);
  };

  /** Each agent with its account's harness and whether that account's binary is found; one whose account is missing or Antigravity's is not found, and `unknown` for its harness when it has none. */
  const listAgents = () => {
    const providers = readAccounts();
    return listed().map((chosen) => {
      try {
        const { harness, command } = chatAccount(providers, chosen);
        return { name: chosen.name, harness, account: chosen.account, model: chosen.model, found: binaryFound(command ?? harness) };
      } catch (error) {
        if (error instanceof ChatRefused === false) throw error;
        return { name: chosen.name, harness: providers[chosen.account]?.harness ?? 'unknown', account: chosen.account, model: chosen.model, found: false };
      }
    });
  };

  /** Takes a child that never ran out: its events, its turns and its row. */
  const discard = (sessionId: string) =>
    db.transaction((tx) => {
      tx.delete(chatEvents).where(eq(chatEvents.sessionId, sessionId)).run();
      tx.delete(chatTurns).where(eq(chatTurns.sessionId, sessionId)).run();
      tx.delete(sessions).where(eq(sessions.id, sessionId)).run();
    });

  /**
   * Starts a child session of `parentId` for a configured agent and sends it the task (ADR 0033). The child is a session of its own agent in the parent's folder,
   * recorded as a plain folder, with the options of that agent lowered to the parent's level. Its row is inserted first, so it holds its slot and its request id
   * while the conversation opens, and goes if the open fails. Everything between the last check and that insert is synchronous, so two calls cannot both take the last slot.
   */
  async function startChild(parentId: string, { agent, task, model, requestId }: { agent: string; task: string; model?: string; requestId?: string }) {
    // a request id seen before is answered with its child, whatever else this call says, and before anything that could refuse it
    const earlier = () => (requestId === undefined ? undefined : db.select({ id: sessions.id }).from(sessions).where(and(eq(sessions.parentSessionId, parentId), eq(sessions.delegationRequestId, requestId))).get());
    const seen = earlier();
    if (seen !== undefined) return { childId: seen.id };

    const parent = row(parentId);
    if (parent.parentSessionId !== null) throw new ChatRefused('A child session cannot start children of its own');
    const chosen = listed().find((candidate) => candidate.name === agent);
    if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${agent}"`);
    if (listAgents().find((candidate) => candidate.name === agent)?.found !== true) throw new ChatRefused(`The agent "${agent}" is not found on this machine`);
    const launch = launchOf(chosen);
    const folder = checkFolder(parent.folder, carrierHome());
    const verdict = (await health({})).agents.find((candidate) => candidate.name === agent)?.state;
    if (verdict === 'signedOut') throw new ChatRefused(`The agent "${agent}" is signed out`);
    if (verdict === 'missing') throw new ChatRefused(`The agent "${agent}" is not found on this machine`);
    if (model !== undefined) await checkModel(agent, model);

    // no await from here to the insert
    const again = earlier();
    if (again !== undefined) return { childId: again.id };
    const current = row(parentId);
    if (deleting.has(parentId)) throw new ChatRefused('This session is being deleted');
    const parentLevel = isScaleHarness(current.harness) ? levelOf(current.harness, optionsOf(parentId, current.options)) : undefined;
    if (parentLevel === undefined || !isScaleHarness(launch.harness)) throw new ChatRefused('This session\'s options are off the permission scale, so a child cannot be given a level');
    const running = db.select({ n: count() }).from(sessions).where(and(eq(sessions.parentSessionId, parentId), inArray(sessions.state, ['working', 'waiting_approval']))).get()?.n ?? 0;
    if (running >= MAX_RUNNING_CHILDREN) throw new ChatRefused(`This session already has ${MAX_RUNNING_CHILDREN} children working or waiting for an approval; start another when one of them has finished`);
    const options = { ...childOptions(launch.harness, { ...(chosen.model && { model: chosen.model }), ...chosen.options }, parentLevel).options, ...(model !== undefined && { model }) };
    const now = clock.now();
    const childId = randomUUID();
    db.insert(sessions).values({ id: childId, agent: chosen.name, harness: launch.harness, folder: current.folder, options, title: titleOf(task), state: 'working', createdAt: now, lastActiveAt: now, parentSessionId: parentId, delegationRequestId: requestId ?? null }).run();

    const issued = issueMcp(childId);
    let conversation: ChatConversation | undefined;
    try {
      conversation = await openConversation(launch, { folder, options, child: true, mcp: issued.args });
      for (const [id, value] of Object.entries(options)) checkOption(conversation.options, id, value);
      if (!exists(parentId) || deleting.has(parentId)) throw new ChatRefused('The session that asked for this child no longer exists');
      deliver(childId, attach(childId, conversation, issued.invocationId), task, task);
    } catch (error) {
      if (lives.has(childId)) await close({ sessionId: childId }); // attached, and the task could not be sent
      else {
        revoke(issued.invocationId);
        await conversation?.close().catch((closing) => log.error('closing a refused conversation failed', closing));
      }
      discard(childId);
      throw error;
    }
    return { childId };
  }

  /** The handoff of a session: its messages stored before `before`, as the conversation after a switch opens with them (ADR 0032). Undefined when it holds no message. */
  const handoffOf = (sessionId: string, before = Number.MAX_SAFE_INTEGER) =>
    buildHandoff(db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), lt(chatEvents.id, before), inArray(chatEvents.kind, ['user', 'assistant']))).orderBy(asc(chatEvents.id)).all().map(({ id, kind, data }) => ({ position: id, kind, data })));

  /** What a conversation that a switch started is opened with again, at each open or resume of it: the handoff from before the notice of the latest switch. Undefined for a session that never switched. */
  const instructionsOf = (sessionId: string) => {
    const notice = db.select({ id: chatEvents.id }).from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'notice'), isNotNull(sql`json_extract(${chatEvents.data}, '$.switched')`))).orderBy(desc(chatEvents.id)).limit(1).get();
    return notice === undefined ? undefined : handoffOf(sessionId, notice.id);
  };

  /**
   * Switches an idle session to another configured agent (ADR 0032): the session keeps its transcript and folder, takes the new agent's harness and defaults and a new
   * conversation that opens with the handoff. The old conversation is closed only after the new one opened with the chat MCP, so a refusal leaves the session as it was.
   * The session is marked as switching from the first await to the end, which every request that touches it checks.
   */
  async function switchAgent({ sessionId, agent }: { sessionId: string; agent: string }) {
    notSwitching(sessionId);
    const current = row(sessionId);
    if (deleting.has(sessionId)) throw new ChatRefused('This session is being deleted');
    refuseChild(sessionId, 'switched to another agent');
    if (current.archived) throw new ChatRefused('This session is archived; restore it first, then switch its agent');
    if (current.plan !== null) throw new ChatRefused('This session did not finish preparing');
    const busy = lives.get(sessionId)?.state ?? current.state;
    if (busy === 'preparing') throw new ChatRefused('This session is being prepared; wait for it to finish, then switch its agent');
    if (busy !== 'idle') throw new ChatRefused(`This session is ${busy === 'working' ? 'working' : 'waiting for an approval'}; interrupt it or wait, then switch its agent`);
    if (agent === current.agent) throw new ChatRefused(`This session already has the agent "${agent}"`);
    const chosen = listed().find((candidate) => candidate.name === agent);
    if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${agent}"`);
    const launch = launchOf(chosen);
    if (listAgents().find((candidate) => candidate.name === agent)?.found !== true) throw new ChatRefused(`The agent "${agent}" is not found on this machine`);

    switching.add(sessionId);
    try {
      const verdict = (await health({})).agents.find((candidate) => candidate.name === agent)?.state;
      if (verdict === 'signedOut') throw new ChatRefused(`The agent "${agent}" is signed out`);
      if (verdict === 'missing') throw new ChatRefused(`The agent "${agent}" is not found on this machine`);
      const folder = checkFolder(current.folder, carrierHome());
      const options = { ...(chosen.model && { model: chosen.model }), ...chosen.options };
      if (options.model !== undefined) await checkModel(agent, options.model);

      const handoff = handoffOf(sessionId);
      const issued = issueMcp(sessionId);
      let conversation: ChatConversation | undefined;
      try {
        conversation = await openConversation(launch, { folder, options, mcp: issued.args, ...(handoff !== undefined && { instructions: handoff }) });
        for (const [id, value] of Object.entries(options)) checkOption(conversation.options, id, value);
        if (mcp !== undefined && (mcp.url() === undefined || conversation.mcpProblem !== undefined)) throw new ChatRefused(`The agent "${agent}" could not get Carrier's own tools, so the session keeps "${current.agent}"`);
        if (!exists(sessionId) || deleting.has(sessionId)) throw new ChatRefused('This session is being deleted');
      } catch (error) {
        revoke(issued.invocationId);
        await conversation?.close().catch((closing) => log.error('closing a refused conversation failed', closing));
        throw error;
      }

      // The new conversation is the session's from here. The old one stays recorded as the session's process until it ends, so a host that dies meanwhile can still sweep it.
      const old = lives.get(sessionId);
      if (old !== undefined) {
        old.detached = true;
        old.cancelIdle?.();
      }
      db.update(sessions).set({ harness: launch.harness, agent: chosen.name, options, nativeId: conversation.nativeId ?? null, lastActiveAt: clock.now() }).where(eq(sessions.id, sessionId)).run();
      attach(sessionId, conversation, issued.invocationId, 'idle', { record: old === undefined });
      store(sessionId, { kind: 'notice', text: `The agent changed from ${current.agent} to ${chosen.name}. ${chosen.name} goes on from a selection of the messages above and can read the rest; reasoning and tool results did not carry over.`, switched: { from: current.agent, to: chosen.name } });
      if (old !== undefined) {
        revoke(old.invocationId);
        await old.conversation.close().catch((closing) => log.error('closing the conversation of the agent that was switched away from failed', closing));
        recordProcess(sessionId, conversation);
      }
      return { session: summary(row(sessionId)), options: conversation.options };
    } finally {
      switching.delete(sessionId);
      const live = lives.get(sessionId);
      if (live !== undefined) armIdle(sessionId, live);
    }
  }

  return {
    liveCount: () => new Set([...lives.keys(), ...preparing.keys()]).size,
    clientJoined() {
      clients++;
      for (const live of lives.values()) live.cancelIdle?.();
    },
    clientLeft() {
      clients--;
      for (const [sessionId, live] of lives) armIdle(sessionId, live);
    },

    agents: listAgents,

    health,
    providers,

    /** What the chat MCP asks of the host. */
    mcpView: {
      exists,
      live: (sessionId: string) => lives.has(sessionId),
      snapshot: (sessionId: string) => {
        const { id, agent, harness, folder, options: stored } = row(sessionId);
        const options = optionsOf(sessionId, stored);
        return { id, agent, harness, folder, model: options.model ?? null, options };
      },
      agents: listAgents,
      startChild,
      agentOptions: (name: string) => {
        const chosen = listed().find((candidate) => candidate.name === name);
        if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${name}"`);
        return { ...chosen.options };
      },
      offer: async (name: string) => (await offerOf({ agent: name })).options,
      health: () => health({}),
      storedEvents: (sessionId: string, { after, kinds, limit }: { after: number; kinds: string[]; limit: number }) =>
        db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), gt(chatEvents.id, after), inArray(chatEvents.kind, kinds))).orderBy(asc(chatEvents.id)).limit(limit).all().map(({ id, kind, data }) => ({ position: id, kind, data })),
      storedEvent: (sessionId: string, position: number, kinds: string[]) => {
        const found = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.id, position), inArray(chatEvents.kind, kinds))).get();
        return found === undefined ? undefined : { position: found.id, kind: found.kind, data: found.data };
      },
      toolStatuses: (sessionId: string, callIds: string[]) => {
        const ends = callIds.length === 0 ? [] : db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'tool_end'), inArray(sql`json_extract(${chatEvents.data}, '$.callId')`, callIds))).all();
        return Object.fromEntries(ends.map(({ data }) => [String(data.callId), data.status === 'ok' ? 'ok' : 'err'])) as Record<string, 'ok' | 'err'>;
      },
    },

    /** The rows, each with `lastMessage`, `turns` and `model` (see `activity`), `kept` (spared by the clock for unsaved work, only while it is due under the current ages) and `deleteAt` (when the clock deletes it, in ms; null unless archived, with both ages set and not kept). */
    list: ({ archived = false }: { archived?: boolean }) => {
      const { archiveAfterDays, deleteAfterDays } = ages();
      return {
        sessions: db.select().from(sessions).where(and(eq(sessions.archived, archived), isNull(sessions.parentSessionId))).orderBy(desc(sessions.lastActiveAt)).all().map((found) => {
          const dueAt = found.archived && archiveAfterDays !== 'never' && deleteAfterDays !== 'never' ? found.lastActiveAt + deleteAfterDays * DAY : null;
          const kept = found.keptAt !== null && dueAt !== null && clock.now() >= dueAt; // a session the clock no longer considers (ages raised or never) is not kept
          return { ...summary(found), live: lives.has(found.id), kept, deleteAt: kept ? null : dueAt, ...activity(found.id) };
        }),
      };
    },

    async open({ agent, folder, options, worktree }: { agent: string; folder: string; options?: Record<string, string>; worktree?: { from: string; name?: string } }) {
      const chosen = listed().find((candidate) => candidate.name === agent);
      if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${agent}"`);
      const real = checkFolder(folder, carrierHome());
      const launch = launchOf(chosen);
      const chosenOptions = { ...(chosen.model && { model: chosen.model }), ...chosen.options, ...options };
      const made = worktree === undefined ? undefined : await exclusive(() => createWorktree(git, real, worktree));
      let conversation: ChatConversation | undefined;
      let created: typeof sessions.$inferSelect;
      const sessionId = randomUUID(); // before the runner opens: its MCP token belongs to this session
      const issued = issueMcp(sessionId);
      // One step: a worktree whose session could not be created is taken away again.
      try {
        conversation = await openConversation(launch, { folder: made?.path ?? real, options: chosenOptions, mcp: issued.args });
        for (const [id, value] of Object.entries(chosenOptions)) checkOption(conversation.options, id, value);
        const now = clock.now();
        created = db
          .insert(sessions)
          .values({
            id: sessionId,
            agent: chosen.name,
            harness: launch.harness,
            folder: made?.path ?? real,
            ...(made !== undefined && { workspaceKind: 'worktree', worktreeBranch: made.branch, worktreeFrom: made.from, worktreeBase: made.base, worktreePath: made.path }),
            options: chosenOptions,
            nativeId: conversation.nativeId ?? null,
            createdAt: now,
            lastActiveAt: now,
          })
          .returning()
          .get();
      } catch (error) {
        revoke(issued.invocationId);
        await conversation?.close().catch((closing) => log.error('closing a refused conversation failed', closing));
        if (made !== undefined) await removeWorktree(git, made);
        throw error;
      }
      attach(created.id, conversation, issued.invocationId);
      return { session: summary(created), options: conversation.options };
    },

    /**
     * Opens a session from a plan: it exists at once as `preparing`, and the steps run in the background and record their events.
     */
    async openPlan({ plan }: { plan: Plan }) {
      if (plan.text.length > chatCaps.message) throw new ChatRefused(`That message has ${plan.text.length} characters; the most a message can have is ${chatCaps.message}`);
      const target = targetOf(plan);
      const now = clock.now();
      const created = db
        .insert(sessions)
        .values({ id: randomUUID(), agent: target.launch.chosen.name, harness: target.launch.harness, folder: target.folder, plan, title: titleOf(plan.text), state: 'preparing', createdAt: now, lastActiveAt: now })
        .returning()
        .get();
      begin(created.id, target, plan); // before the answer, so the host is never idle between the reply and the first step
      return { session: summary(created) };
    },

    /** Repeats the steps of a failed preparation that did not finish; what was made (the worktree, the checkout) is reused. */
    async retryPreparation({ sessionId }: { sessionId: string }) {
      const current = row(sessionId);
      if (current.state === 'preparing') throw new ChatRefused('This session is still being prepared, so there is nothing to try again');
      if (current.plan === null || preparing.has(sessionId)) throw new ChatRefused('This session is not in a failed preparation, so there is nothing to try again');
      if (deleting.has(sessionId)) throw new ChatRefused('This session is being deleted');
      const target = targetOf(current.plan);
      const updated = db.update(sessions).set({ state: 'preparing', lastActiveAt: clock.now() }).where(eq(sessions.id, sessionId)).returning().get();
      begin(sessionId, target, current.plan);
      return { session: summary(updated) };
    },

    /** Stops the step that is running and deletes the session as a delete does, its worktree with it; answers the plan, for the app to put back in the draft. */
    async cancelPreparation({ sessionId }: { sessionId: string }) {
      const { state, plan } = row(sessionId);
      if (state !== 'preparing') throw new ChatRefused('This session is not being prepared, so there is nothing to cancel');
      deleting.add(sessionId); // a retry or a resume that comes in meanwhile is refused
      try {
        const running = preparing.get(sessionId);
        running?.abort.abort();
        await running?.done;
        await close({ sessionId }); // the agent that waits to answer the first message
        db.update(sessions).set({ state: 'idle' }).where(eq(sessions.id, sessionId)).run();
        await deleteSession({ sessionId });
      } finally {
        deleting.delete(sessionId);
      }
      return { plan };
    },

    agentOptions: offerOf,

    /** Opens a closed session again from its stored native id, folder and options; a live one is just attached to. */
    async resume({ sessionId }: { sessionId: string }) {
      refuseChild(sessionId, 'resumed');
      notSwitching(sessionId);
      const current = row(sessionId);
      if (current.plan !== null) throw new ChatRefused('This session did not finish preparing');
      const present = lives.get(sessionId);
      if (present !== undefined) return { session: summary(current), options: present.conversation.options };
      if (deleting.has(sessionId)) throw new ChatRefused('This session is being deleted');
      const chosen = listed().find((candidate) => candidate.name === current.agent);
      if (chosen === undefined) throw new ChatRefused(`The agent "${current.agent}" of this session is not configured any more`);
      const launch = launchOf(chosen);
      const folder = checkFolder(current.folder, carrierHome());
      // a session that never got a native id (nothing was said) has nothing to resume: it starts again, as it was opened
      const issued = issueMcp(sessionId);
      let conversation: ChatConversation;
      try {
        const instructions = instructionsOf(sessionId);
        conversation = await openConversation(launch, { folder, options: current.options ?? {}, mcp: issued.args, ...(current.nativeId !== null && { resume: current.nativeId }), ...(instructions !== undefined && { instructions }) });
      } catch (error) {
        revoke(issued.invocationId);
        throw error;
      }
      if (lives.has(sessionId)) {
        // another client resumed it while this one waited for the provider: only this one's token goes
        revoke(issued.invocationId);
        await conversation.close();
        return { session: summary(row(sessionId)), options: lives.get(sessionId)!.conversation.options };
      }
      if (deleting.has(sessionId) || !exists(sessionId)) {
        // the session was deleted (or is being) while this one waited for the provider: nothing may stay attached to its folder
        revoke(issued.invocationId);
        await conversation.close();
        throw new ChatRefused('This session is being deleted');
      }
      attach(sessionId, conversation, issued.invocationId);
      if (conversation.startedOver) {
        // The dead id goes: with it kept, every wake that closes before a first message would try it again and say this again. The notice keeps it.
        store(sessionId, { kind: 'notice', text: 'The agent could not find this conversation, so this is a new one in the same folder: it does not remember what is above.', ...(current.nativeId !== null && { lostNativeId: current.nativeId }) });
        db.update(sessions).set({ nativeId: null }).where(eq(sessions.id, sessionId)).run();
        return { session: summary(row(sessionId)), options: conversation.options };
      }
      return { session: summary(current), options: conversation.options };
    },

    send({ sessionId, text, command }: { sessionId: string; text: string; command?: string }) {
      refuseChild(sessionId, 'sent a message');
      if (text.length > chatCaps.message) throw new ChatRefused(`That message has ${text.length} characters; the most a message can have is ${chatCaps.message}`);
      notSwitching(sessionId);
      const current = row(sessionId);
      const live = lives.get(sessionId);
      if (live === undefined) throw new ChatRefused('This session is closed');
      if (live.state !== 'idle') throw new ChatRefused('The agent is still answering');
      // a command is named by the id the session listed; what the person sees of it is a slash and its name, whatever the provider does with it
      const invoked = command === undefined ? undefined : live.conversation.commands.find((candidate) => candidate.id === command);
      if (command !== undefined && invoked === undefined) throw new ChatRefused('This session does not list that command');
      const shown = invoked === undefined ? text : `/${invoked.name}${text === '' ? '' : ` ${text}`}`;
      if (shown.length > chatCaps.message) throw new ChatRefused(`That message has ${shown.length} characters; the most a message can have is ${chatCaps.message}`);
      if (current.title === null) db.update(sessions).set({ title: titleOf(shown) }).where(eq(sessions.id, sessionId)).run();
      deliver(sessionId, live, shown, text, invoked);
      return {};
    },

    /** Passes the person's choice for a pending approval to the agent; the adapter says it was answered and the host records that. */
    answer({ sessionId, approvalId, choiceId, answers }: { sessionId: string; approvalId: string; choiceId: string; answers?: Record<string, string> }) {
      notSwitching(sessionId);
      row(sessionId);
      const live = lives.get(sessionId);
      if (live === undefined) throw new ChatRefused('This session is closed');
      const approval = live.approvals.get(approvalId);
      if (approval === undefined) throw new ChatRefused('That approval is not pending: it is unknown or was already answered');
      if (approval.choices.some((choice) => choice.id === choiceId) === false) throw new ChatRefused(`"${choiceId}" is not one of the choices: ${approval.choices.map((choice) => choice.id).join(', ')}`);
      if (approval.questions === undefined && answers !== undefined) throw new ChatRefused('That approval asks no questions, so it takes no answers');
      if (approval.questions !== undefined && choiceId === 'allow') {
        if (answers === undefined) throw new ChatRefused('Answer the questions first');
        const stray = Object.keys(answers).find((key) => approval.questions!.some((q) => q.question === key) === false);
        if (stray !== undefined) throw new ChatRefused(`"${stray}" is not one of the questions`);
      }
      live.approvals.delete(approvalId); // before the agent hears it, so a second answer finds nothing
      try {
        live.conversation.answer(approvalId, choiceId, answers);
      } catch (error) {
        live.approvals.set(approvalId, approval);
        if (error instanceof ChatRefused) throw error;
        log.error('an answer could not be delivered to the agent', error);
        throw new ChatRefused('The answer could not be delivered to the agent');
      }
      return {};
    },

    /** Ends the turn that is running, if any, and leaves the session idle for the next message. With no turn running it changes nothing. */
    async interrupt({ sessionId }: { sessionId: string }) {
      notSwitching(sessionId);
      row(sessionId);
      const live = lives.get(sessionId);
      if (live?.turn === undefined) return {};
      try {
        await live.conversation.interrupt();
      } catch (error) {
        log.error('interrupting a conversation failed', error);
      }
      // The adapter says the turn ended; if it did not, the interrupt still did, so the host records it.
      if (live.turn !== undefined) onEvent(sessionId, live, { kind: 'turn_end', outcome: 'interrupted' });
      return {};
    },

    async setOption({ sessionId, option, value }: { sessionId: string; option: string; value: string }) {
      refuseChild(sessionId, 'given other options');
      notSwitching(sessionId);
      const live = lives.get(sessionId);
      if (live === undefined) throw new ChatRefused('This session is closed');
      checkOption(live.conversation.options, option, value);
      try {
        await live.conversation.setOption(option, value);
      } catch (error) {
        if (error instanceof ChatRefused) throw error;
        log.error('an option could not be changed', error);
        throw new ChatRefused(`The option "${option}" could not be changed`);
      }
      return { options: live.conversation.options };
    },

    /** `reasoning` is the client asking for the `reasoning` events: one that does not keeps getting the events it knew. */
    events({ sessionId, after = 0, limit, reasoning = false }: { sessionId: string; after?: number; limit: number; reasoning?: boolean }) {
      const current = row(sessionId);
      const rows = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), gt(chatEvents.id, after), reasoning ? undefined : ne(chatEvents.kind, 'reasoning'))).orderBy(asc(chatEvents.id)).limit(limit).all();
      const live = lives.get(sessionId);
      return {
        // an option event's data has the option's own `id`, which must not take the place of the row's: a client reads `id` as the cursor
        events: rows.map(({ id, at, kind, data }) => (kind === 'option' ? { id, at, kind, option: data.id, value: data.value } : { id, at, kind, ...data })),
        cursor: rows.at(-1)?.id ?? after,
        session: summary(current),
        streaming: live?.streaming ?? '',
        progress: progress.get(sessionId) ?? null,
        approvals: [...(live?.approvals.values() ?? [])],
        options: live?.conversation.options ?? [],
        commands: live?.conversation.commands ?? [],
      };
    },

    close: async ({ sessionId }: { sessionId: string }) => {
      notSwitching(sessionId);
      return close({ sessionId });
    },

    switchAgent,

    /** Sets or clears the archived mark. A live idle session is closed first; a working or waiting one is refused. */
    async archive({ sessionId, archived }: { sessionId: string; archived: boolean }) {
      refuseChild(sessionId, archived ? 'archived' : 'restored');
      if (archived) await settle(sessionId, 'archive');
      else row(sessionId);
      db.update(sessions).set({ archived, ...(archived === false && { lastActiveAt: clock.now(), keptAt: null }) }).where(eq(sessions.id, sessionId)).run();
      return {};
    },

    /** Sets the title (first line, cut like an automatic one); fine while the session works. The first message only names an untitled session, so it never replaces this. */
    rename({ sessionId, title }: { sessionId: string; title: string }) {
      refuseChild(sessionId, 'renamed');
      const named = titleOf(title);
      if (named === '') throw new ChatRefused('A title cannot be empty');
      db.update(sessions).set({ title: named }).where(eq(sessions.id, sessionId)).run();
      return {};
    },

    /**
     * The clock's pass: archives each session left alone for `archiveAfterDays`, then deletes each archived one left alone for `deleteAfterDays`, sparing
     * (marking `keptAt`) one whose worktree holds unsaved work. A working, waiting or live one is looked at again on the next pass.
     */
    async applyClock({ archiveAfterDays, deleteAfterDays }: SessionAges) {
      const now = clock.now();
      for (const found of db.select().from(sessions).where(eq(sessions.archived, false)).all()) {
        if (idleFor(found, lives.has(found.id), now, archiveAfterDays)) db.update(sessions).set({ archived: true }).where(eq(sessions.id, found.id)).run();
      }
      if (archiveAfterDays === 'never') return;
      for (const { id } of db.select().from(sessions).where(eq(sessions.archived, true)).all()) {
        if (closed) return;
        try {
          // read again after each wait: the person may have restored or resumed it meanwhile, or the host may be shutting down
          const due = () => {
            if (closed) return undefined;
            const found = db.select().from(sessions).where(eq(sessions.id, id)).get();
            return found?.archived === true && idleFor(found, lives.has(id), now, deleteAfterDays) ? found : undefined;
          };
          const found = due();
          if (found === undefined) continue;
          if (found.workspaceKind === 'worktree') {
            // one session at a time and just before deleting it, so a commit shared with one deleted a moment ago counts as lost
            const { dirty, unpushed } = await previewWorktree(git, { path: found.worktreePath!, branch: found.worktreeBranch!, from: found.worktreeFrom!, base: found.worktreeBase! }, [found.worktreeBranch!]);
            if (due() === undefined) continue;
            if (dirty > 0 || unpushed > 0) {
              if (found.keptAt === null) db.update(sessions).set({ keptAt: now }).where(eq(sessions.id, id)).run();
              continue;
            }
          }
          await deleteSession({ sessionId: id });
        } catch (error) {
          log.error('the clock could not delete a session; the next pass tries again', error); // git cannot read it, or it cannot be removed: left alone
        }
      }
    },

    /** Removes the session with all its events and turns. A live idle session is closed first; a working or waiting one is refused. */
    async delete(args: { sessionId: string }) {
      refuseChild(args.sessionId, 'deleted');
      return deleteSession(args);
    },

    /** What deleting these sessions would discard: for each one in a worktree, its uncommitted files and the commits that exist nowhere else. An unknown id refuses the whole request. */
    async deletePreview({ sessionIds }: { sessionIds: string[] }) {
      const found = sessionIds.map(row);
      // A commit shared by two of them is lost with both, so each one's preview excludes every branch of the batch.
      const batch = found.flatMap(({ workspaceKind, worktreeBranch }) => (workspaceKind === 'worktree' ? [worktreeBranch!] : []));
      // One session after another: a worktree reads two git processes, and the preview is a one-off, not a hot path.
      const previews = [];
      for (const { id, workspaceKind, worktreeBranch, worktreeFrom, worktreeBase, worktreePath } of found) {
        previews.push({
          sessionId: id,
          worktree: workspaceKind === 'worktree' ? { path: worktreePath!, branch: worktreeBranch!, ...(await previewWorktree(git, { path: worktreePath!, branch: worktreeBranch!, from: worktreeFrom!, base: worktreeBase! }, batch)) } : null,
        });
      }
      return { sessions: previews };
    },

    /** What a folder is as a git repository, for the person to choose how to work in it. */
    workspace: async ({ folder }: { folder: string }) => inspectFolder(git, checkFolder(folder, carrierHome())),

    /** Fetches `origin` of a folder and answers what it is after it. */
    fetch: async ({ folder }: { folder: string }) => fetchFolder(git, checkFolder(folder, carrierHome())),

    /** A free name for a worktree of a folder, from the StarCraft word lists. */
    suggestName: async ({ folder }: { folder: string }) => suggestName(git, checkFolder(folder, carrierHome())),

    /** Whether a typed worktree name is valid and free. */
    checkName: async ({ folder, name }: { folder: string; name: string }) => checkName(git, checkFolder(folder, carrierHome()), name),

    /** Closes every live session: the host's stop. */
    async closeAll() {
      closed = true;
      for (const sessionId of [...lives.keys()]) await close({ sessionId });
      await Promise.all(ending);
    },
  };
}

export type ChatSessions = ReturnType<typeof createSessions>;
