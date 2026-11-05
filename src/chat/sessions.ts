import { accessSync, constants } from 'node:fs';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { and, asc, desc, eq, gt, isNotNull } from 'drizzle-orm';
import { createScopedLogger } from '@ashulab/universal-logger';
import { carrierHome } from '../config/default-path.ts';
import type { ChatAgent } from './config.ts';
import { resolveBinary } from '../harnesses/common.ts';
import type { Clock } from '../orchestration/clock.ts';
import type { ChatDb } from './db.ts';
import { checkFolder } from './folder.ts';
import { createHealth, realProbes, type HealthProbes } from './health.ts';
import type { Git } from './git.ts';
import type { Plan, Step, StepEvent } from './plan.ts';
import { ChatRefused, type ChatChoice, type ChatCommand, type ChatConversation, type ChatEvent, type ChatOption, type ChatRunner } from './runner.ts';
import { chatEvents, chatTurns, sessions } from './schema.ts';
import { boundEvent, chatCaps, titleOf } from './transcript.ts';
import { checkName, suggestName } from './names.ts';
import { createWorktree, deleteWorktree, previewWorktree, removeWorktree } from './worktree.ts';
import { checkout, fetchFolder, inspectFolder } from './workspace.ts';

const log = createScopedLogger('chat');

export const IDLE_CLOSE_MS = 60_000;

type Harness = (typeof sessions.$inferSelect)['harness'];
type State = (typeof sessions.$inferSelect)['state'];

/** Where a session works: the folder it was opened in, or a worktree made for it from that base folder. */
export type SessionWorkspace = { kind: 'folder' } | { kind: 'worktree'; branch: string; from: string; base: string; path: string };

export type SessionSummary = Omit<typeof sessions.$inferSelect, 'options' | 'pid' | 'pgid' | 'command' | 'plan' | 'workspaceKind' | 'worktreeBranch' | 'worktreeFrom' | 'worktreeBase' | 'worktreePath'> & {
  workspace: SessionWorkspace;
  /** `running` while the host prepares the session, `failed` when a step failed and the plan is kept, null otherwise. */
  preparation: 'running' | 'failed' | null;
};

export type PendingApproval = { approvalId: string; tool: string; arg?: string; choices: ChatChoice[] };

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
};

export type ChatSessionsDeps = {
  db: ChatDb;
  /** The agents a chat can start with, in the order `chat.json` lists them. */
  agents: ChatAgent[];
  clock: Clock;
  /** The runner of each harness; a harness with none cannot be opened. */
  runners: Partial<Record<Harness, ChatRunner>>;
  env: NodeJS.ProcessEnv;
  /** The `git` of the machine. */
  git: Git;
  /** Whether an agent's binary is there. */
  binaryFound: (command: string) => boolean;
  /** What the `health` request runs; the machine's own tools unless a test replaces it. */
  probes?: HealthProbes;
  /** Called when a session becomes or stops being live, so the host can start or cancel its own countdown. */
  onLiveChange: () => void;
};

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
export function createSessions({ db, agents, clock, runners, env, git, binaryFound, probes = realProbes, onLiveChange }: ChatSessionsDeps) {
  const health = createHealth({ agents, clock, binaryFound, probes });
  const lives = new Map<string, Live>();
  // Sessions being deleted: no agent may open in their folder while it is removed.
  const deleting = new Set<string>();
  let clients = 0;

  const row = (sessionId: string) => {
    const found = db.select().from(sessions).where(eq(sessions.id, sessionId)).get();
    if (found === undefined) throw new ChatRefused('There is no such session');
    return found;
  };
  const summary = ({ options: _options, pid: _pid, pgid: _pgid, command: _command, plan, workspaceKind, worktreeBranch, worktreeFrom, worktreeBase, worktreePath, ...rest }: typeof sessions.$inferSelect): SessionSummary => ({
    ...rest,
    preparation: rest.state === 'preparing' ? 'running' : plan === null ? null : 'failed',
    workspace: workspaceKind === 'worktree' ? { kind: 'worktree', branch: worktreeBranch!, from: worktreeFrom!, base: worktreeBase!, path: worktreePath! } : { kind: 'folder' },
  });

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
    live.cancelIdle = live.state === 'idle' && clients === 0 ? clock.after(IDLE_CLOSE_MS, async () => void (await close({ sessionId }))) : undefined;
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

  // Sessions whose steps run in the background and are not live yet: the host is not idle while one does.
  const preparing = new Set<string>();
  const stepEvent = (sessionId: string, step: Step, status: StepEvent['status'], detail?: string) => store(sessionId, { kind: 'step', step, status, ...(detail !== undefined && { detail }) });
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
      db.insert(chatTurns).values({ sessionId, startedAt, model: event.model ?? null, outcome: event.outcome, durationMs: clock.now() - startedAt, toolCalls: live.turn?.toolCalls ?? 0, usage: event.usage ?? null }).run();
      live.turn = undefined;
    }
    touch(sessionId, live, event.kind === 'approval' ? 'waiting_approval' : event.kind === 'turn_end' ? 'idle' : event.kind === 'approval_answered' ? 'working' : live.state);
  };

  async function close({ sessionId }: { sessionId: string }) {
    row(sessionId);
    const live = lives.get(sessionId);
    if (live === undefined) return {};
    lives.delete(sessionId);
    live.cancelIdle?.();
    db.update(sessions).set({ state: 'idle', pid: null, pgid: null, command: null }).where(eq(sessions.id, sessionId)).run();
    try {
      await live.conversation.close();
    } catch (error) {
      log.error('closing a conversation failed', error);
    }
    onLiveChange();
    return {};
  }

  /** Readies a session to be archived or deleted: refuses an unknown one, and one working or waiting for an approval; closes an idle live one. */
  async function settle(sessionId: string, verb: 'archive' | 'delete') {
    if (row(sessionId).state === 'preparing') throw new ChatRefused(`This session is being prepared; wait for it to finish, then ${verb} it`);
    const live = lives.get(sessionId);
    if (live === undefined) return;
    if (live.state !== 'idle') throw new ChatRefused(`This session is ${live.state === 'working' ? 'working' : 'waiting for an approval'}; interrupt or close it first, then ${verb} it`);
    await close({ sessionId });
    if (lives.has(sessionId)) throw new ChatRefused('This session was resumed meanwhile; close it first'); // a resume that finished during the close
  }

  async function openConversation(chosen: ChatAgent, runner: ChatRunner, args: { folder: string; options: Record<string, string>; resume?: string }) {
    try {
      return await runner.open({ ...args, command: chosen.command, env });
    } catch (error) {
      if (error instanceof ChatRefused) throw error;
      log.error('a chat runner failed to open', error);
      throw new ChatRefused(`${chosen.name} could not be started`);
    }
  }

  /** Makes a conversation the live one of a session. */
  const attach = (sessionId: string, conversation: ChatConversation, state: State = 'idle') => {
    const live: Live = { conversation, state, streaming: '', approvals: new Map() };
    lives.set(sessionId, live);
    const { pid = null, pgid = null, command = null } = conversation.process ?? {};
    db.update(sessions).set({ pid, pgid, command }).where(eq(sessions.id, sessionId)).run();
    conversation.onEvent((event) => {
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
    armIdle(sessionId, live);
    onLiveChange();
    return live;
  };

  /**
   * The `worktree` or `checkout` step of a plan, when it has one: the folder the agent runs in, or undefined once the step failed and was recorded.
   * A worktree already recorded on the session is the one made before, so it is reused and not made twice.
   */
  async function arrange(sessionId: string, folder: string, plan: Plan): Promise<string | undefined> {
    const { worktree, branch } = plan;
    if (worktree === undefined && branch === undefined) return folder;
    const step = worktree === undefined ? 'checkout' : 'worktree';
    const recorded = row(sessionId);
    if (recorded.workspaceKind === 'worktree') return recorded.worktreePath!;
    stepEvent(sessionId, step, 'running');
    try {
      if (worktree !== undefined) {
        if (branch === undefined) throw new ChatRefused('A worktree needs the branch it starts from');
        // an empty name is the host's to generate
        const made = await exclusive(() => createWorktree(git, folder, { from: branch, ...(worktree.name !== undefined && worktree.name !== '' && { name: worktree.name }) }));
        db.update(sessions).set({ folder: made.path, workspaceKind: 'worktree', worktreeBranch: made.branch, worktreeFrom: made.from, worktreeBase: made.base, worktreePath: made.path }).where(eq(sessions.id, sessionId)).run();
        stepEvent(sessionId, step, 'done');
        return made.path;
      }
      await checkout(git, folder, branch!);
      stepEvent(sessionId, step, 'done');
      return folder;
    } catch (error) {
      if (error instanceof ChatRefused === false) log.error(`preparing a session failed at ${step}`, error);
      failStep(sessionId, step, error instanceof ChatRefused ? error.message : `The ${step} could not be done`);
    }
  }

  /** The steps of a plan, in the background: it never throws, a failure is recorded as a step that failed. */
  async function prepare(sessionId: string, chosen: ChatAgent, runner: ChatRunner, base: string, plan: Plan) {
    try {
      const folder = await arrange(sessionId, base, plan);
      if (folder === undefined) return;
      stepEvent(sessionId, 'agent', 'running');
      const options = { ...(chosen.model && { model: chosen.model }), ...chosen.options, ...plan.options };
      let conversation: ChatConversation | undefined;
      try {
        conversation = await openConversation(chosen, runner, { folder, options });
        for (const [id, value] of Object.entries(options)) checkOption(conversation.options, id, value);
      } catch (error) {
        await conversation?.close().catch((closing) => log.error('closing a refused conversation failed', closing));
        if (error instanceof ChatRefused === false) log.error('preparing a session failed at the agent', error);
        return failStep(sessionId, 'agent', error instanceof ChatRefused ? error.message : 'The agent could not be started');
      }
      stepEvent(sessionId, 'agent', 'done');
      const live = attach(sessionId, conversation, 'preparing');
      stepEvent(sessionId, 'message', 'running');
      live.awaitingAnswer = true;
      live.turn = { startedAt: clock.now(), toolCalls: 0 };
      store(sessionId, { kind: 'user', text: plan.text });
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

  /** What each agent offered when it was last asked (a draft lists the models before a session exists), kept ten minutes. */
  const offered = new Map<string, { at: number; offer: Promise<{ options: ChatOption[]; commands: ChatCommand[] }> }>();

  return {
    liveCount: () => new Set([...lives.keys(), ...preparing]).size,
    clientJoined() {
      clients++;
      for (const live of lives.values()) live.cancelIdle?.();
    },
    clientLeft() {
      clients--;
      for (const [sessionId, live] of lives) armIdle(sessionId, live);
    },

    agents: () => agents.map(({ name, harness, model, command }) => ({ name, harness, model, found: binaryFound(command ?? harness) })),

    health,

    list: ({ archived = false }: { archived?: boolean }) => ({
      sessions: db.select().from(sessions).where(eq(sessions.archived, archived)).orderBy(desc(sessions.lastActiveAt)).all().map((found) => ({ ...summary(found), live: lives.has(found.id) })),
    }),

    async open({ agent, folder, options, worktree }: { agent: string; folder: string; options?: Record<string, string>; worktree?: { from: string; name?: string } }) {
      const chosen = agents.find((candidate) => candidate.name === agent);
      if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${agent}"`);
      const real = checkFolder(folder, carrierHome());
      const runner = runners[chosen.harness];
      if (runner === undefined) throw new ChatRefused(`This host has no chat runner for ${chosen.harness}`);
      const chosenOptions = { ...(chosen.model && { model: chosen.model }), ...chosen.options, ...options };
      const made = worktree === undefined ? undefined : await exclusive(() => createWorktree(git, real, worktree));
      let conversation: ChatConversation | undefined;
      let created: typeof sessions.$inferSelect;
      // One step: a worktree whose session could not be created is taken away again.
      try {
        conversation = await openConversation(chosen, runner, { folder: made?.path ?? real, options: chosenOptions });
        for (const [id, value] of Object.entries(chosenOptions)) checkOption(conversation.options, id, value);
        const now = clock.now();
        created = db
          .insert(sessions)
          .values({
            id: randomUUID(),
            agent: chosen.name,
            harness: chosen.harness,
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
        await conversation?.close().catch((closing) => log.error('closing a refused conversation failed', closing));
        if (made !== undefined) await removeWorktree(git, made);
        throw error;
      }
      attach(created.id, conversation);
      return { session: summary(created), options: conversation.options };
    },

    /**
     * Opens a session from a plan: it exists at once as `preparing`, and the steps run in the background and record their events. Only a plan for a
     * folder runs yet, with the branch to check out or a worktree from it.
     */
    async openPlan({ plan }: { plan: Plan }) {
      if (plan.workspace.kind !== 'folder') throw new ChatRefused('A plan for a repository or a project is not supported yet; only a folder');
      if (plan.text.length > chatCaps.message) throw new ChatRefused(`That message has ${plan.text.length} characters; the most a message can have is ${chatCaps.message}`);
      const chosen = agents.find((candidate) => candidate.name === plan.agent);
      if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${plan.agent}"`);
      const runner = runners[chosen.harness];
      if (runner === undefined) throw new ChatRefused(`This host has no chat runner for ${chosen.harness}`);
      const folder = checkFolder(plan.workspace.folder, carrierHome());
      const now = clock.now();
      const created = db
        .insert(sessions)
        .values({ id: randomUUID(), agent: chosen.name, harness: chosen.harness, folder, plan, title: titleOf(plan.text), state: 'preparing', createdAt: now, lastActiveAt: now })
        .returning()
        .get();
      preparing.add(created.id); // before the answer, so the host is never idle between the reply and the first step
      void prepare(created.id, chosen, runner, folder, plan);
      return { session: summary(created) };
    },

    /**
     * The options and the commands an agent offers, with the values it would start with, before any session exists: it starts the agent in a folder of
     * nobody's, reads what it lists and ends it. Kept ten minutes, and a failure is not kept.
     */
    async agentOptions({ agent }: { agent: string }) {
      const chosen = agents.find((candidate) => candidate.name === agent);
      if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${agent}"`);
      const runner = runners[chosen.harness];
      if (runner === undefined) throw new ChatRefused(`This host has no chat runner for ${chosen.harness}`);
      const known = offered.get(agent);
      if (known !== undefined && clock.now() - known.at < 10 * 60_000) return await known.offer;
      const offer = (async () => {
        const conversation = await openConversation(chosen, runner, { folder: tmpdir(), options: { ...(chosen.model && { model: chosen.model }), ...chosen.options } });
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
    },

    /** Opens a closed session again from its stored native id, folder and options; a live one is just attached to. */
    async resume({ sessionId }: { sessionId: string }) {
      const current = row(sessionId);
      if (current.plan !== null) throw new ChatRefused('This session did not finish preparing');
      const present = lives.get(sessionId);
      if (present !== undefined) return { session: summary(current), options: present.conversation.options };
      if (deleting.has(sessionId)) throw new ChatRefused('This session is being deleted');
      const chosen = agents.find((candidate) => candidate.name === current.agent);
      if (chosen === undefined) throw new ChatRefused(`The agent "${current.agent}" of this session is not configured any more`);
      const runner = runners[chosen.harness];
      if (runner === undefined) throw new ChatRefused(`This host has no chat runner for ${chosen.harness}`);
      const folder = checkFolder(current.folder, carrierHome());
      // a session that never got a native id (nothing was said) has nothing to resume: it starts again, as it was opened
      const conversation = await openConversation(chosen, runner, { folder, options: current.options ?? {}, ...(current.nativeId !== null && { resume: current.nativeId }) });
      if (lives.has(sessionId)) {
        // another client resumed it while this one waited for the provider
        await conversation.close();
        return { session: summary(row(sessionId)), options: lives.get(sessionId)!.conversation.options };
      }
      if (deleting.has(sessionId)) {
        // the session was deleted while this one waited for the provider: nothing may stay attached to its folder
        await conversation.close();
        throw new ChatRefused('This session is being deleted');
      }
      attach(sessionId, conversation);
      return { session: summary(current), options: conversation.options };
    },

    send({ sessionId, text, command }: { sessionId: string; text: string; command?: string }) {
      if (text.length > chatCaps.message) throw new ChatRefused(`That message has ${text.length} characters; the most a message can have is ${chatCaps.message}`);
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
      return {};
    },

    /** Passes the person's choice for a pending approval to the agent; the adapter says it was answered and the host records that. */
    answer({ sessionId, approvalId, choiceId }: { sessionId: string; approvalId: string; choiceId: string }) {
      row(sessionId);
      const live = lives.get(sessionId);
      if (live === undefined) throw new ChatRefused('This session is closed');
      const approval = live.approvals.get(approvalId);
      if (approval === undefined) throw new ChatRefused('That approval is not pending: it is unknown or was already answered');
      if (approval.choices.some((choice) => choice.id === choiceId) === false) throw new ChatRefused(`"${choiceId}" is not one of the choices: ${approval.choices.map((choice) => choice.id).join(', ')}`);
      live.approvals.delete(approvalId); // before the agent hears it, so a second answer finds nothing
      try {
        live.conversation.answer(approvalId, choiceId);
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
      row(sessionId);
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

    events({ sessionId, after = 0, limit }: { sessionId: string; after?: number; limit: number }) {
      const current = row(sessionId);
      const rows = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), gt(chatEvents.id, after))).orderBy(asc(chatEvents.id)).limit(limit).all();
      const live = lives.get(sessionId);
      return {
        // an option event's data has the option's own `id`, which must not take the place of the row's: a client reads `id` as the cursor
        events: rows.map(({ id, at, kind, data }) => (kind === 'option' ? { id, at, kind, option: data.id, value: data.value } : { id, at, kind, ...data })),
        cursor: rows.at(-1)?.id ?? after,
        session: summary(current),
        streaming: live?.streaming ?? '',
        approvals: [...(live?.approvals.values() ?? [])],
        options: live?.conversation.options ?? [],
        commands: live?.conversation.commands ?? [],
      };
    },

    close,

    /** Sets or clears the archived mark. A live idle session is closed first; a working or waiting one is refused. */
    async archive({ sessionId, archived }: { sessionId: string; archived: boolean }) {
      if (archived) await settle(sessionId, 'archive');
      else row(sessionId);
      db.update(sessions).set({ archived }).where(eq(sessions.id, sessionId)).run();
      return {};
    },

    /** Removes the session with all its events and turns. A live idle session is closed first; a working or waiting one is refused. */
    async delete({ sessionId }: { sessionId: string }) {
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
      for (const sessionId of [...lives.keys()]) await close({ sessionId });
    },
  };
}

export type ChatSessions = ReturnType<typeof createSessions>;
