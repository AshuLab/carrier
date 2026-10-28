import { accessSync, constants } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { and, asc, desc, eq, gt } from 'drizzle-orm';
import { createScopedLogger } from '@ashulab/universal-logger';
import { chatAgents } from '../config/chat-agents.ts';
import type { Config } from '../config/schema.ts';
import { resolveBinary } from '../harnesses/common.ts';
import type { Clock } from '../orchestration/clock.ts';
import type { ChatDb } from './db.ts';
import { checkFolder } from './folder.ts';
import type { Git } from './git.ts';
import { ChatRefused, type ChatChoice, type ChatConversation, type ChatEvent, type ChatOption, type ChatRunner } from './runner.ts';
import { chatEvents, chatTurns, sessions } from './schema.ts';
import { boundEvent, chatCaps, titleOf } from './transcript.ts';
import { checkName, suggestName } from './names.ts';
import { createWorktree, deleteWorktree, previewWorktree, removeWorktree } from './worktree.ts';
import { fetchFolder, inspectFolder } from './workspace.ts';

const log = createScopedLogger('chat');

export const IDLE_CLOSE_MS = 60_000;

type Harness = (typeof sessions.$inferSelect)['harness'];
type State = (typeof sessions.$inferSelect)['state'];

/** Where a session works: the folder it was opened in, or a worktree made for it from that base folder. */
export type SessionWorkspace = { kind: 'folder' } | { kind: 'worktree'; branch: string; from: string; base: string; path: string };

export type SessionSummary = Omit<typeof sessions.$inferSelect, 'options' | 'pid' | 'pgid' | 'command' | 'workspaceKind' | 'worktreeBranch' | 'worktreeFrom' | 'worktreeBase' | 'worktreePath'> & { workspace: SessionWorkspace };

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
  cancelIdle?: () => void;
};

export type ChatSessionsDeps = {
  db: ChatDb;
  config: Config;
  clock: Clock;
  /** The runner of each harness; a harness with none cannot be opened. */
  runners: Partial<Record<Harness, ChatRunner>>;
  env: NodeJS.ProcessEnv;
  /** The `git` of the machine. */
  git: Git;
  /** Whether an agent's binary is there. */
  binaryFound: (command: string) => boolean;
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
export function createSessions({ db, config, clock, runners, env, git, binaryFound, onLiveChange }: ChatSessionsDeps) {
  const lives = new Map<string, Live>();
  let clients = 0;

  const row = (sessionId: string) => {
    const found = db.select().from(sessions).where(eq(sessions.id, sessionId)).get();
    if (found === undefined) throw new ChatRefused('There is no such session');
    return found;
  };
  const summary = ({ options: _options, pid: _pid, pgid: _pgid, command: _command, workspaceKind, worktreeBranch, worktreeFrom, worktreeBase, worktreePath, ...rest }: typeof sessions.$inferSelect): SessionSummary => ({
    ...rest,
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
  const store = (sessionId: string, event: ChatEvent) => {
    const data = boundEvent(event);
    if (data !== undefined) db.insert(chatEvents).values({ sessionId, at: clock.now(), kind: event.kind, data }).run();
  };

  const onEvent = (sessionId: string, live: Live, event: ChatEvent) => {
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
    row(sessionId);
    const live = lives.get(sessionId);
    if (live === undefined) return;
    if (live.state !== 'idle') throw new ChatRefused(`This session is ${live.state === 'working' ? 'working' : 'waiting for an approval'}; interrupt or close it first, then ${verb} it`);
    await close({ sessionId });
    if (lives.has(sessionId)) throw new ChatRefused('This session was resumed meanwhile; close it first'); // a resume that finished during the close
  }

  async function openConversation(chosen: ReturnType<typeof chatAgents>[number], runner: ChatRunner, args: { folder: string; options: Record<string, string>; resume?: string }) {
    try {
      return await runner.open({ ...args, command: chosen.command, env });
    } catch (error) {
      if (error instanceof ChatRefused) throw error;
      log.error('a chat runner failed to open', error);
      throw new ChatRefused(`${chosen.name} could not be started`);
    }
  }

  /** Makes a conversation the live one of a session. */
  const attach = (sessionId: string, conversation: ChatConversation) => {
    const live: Live = { conversation, state: 'idle', streaming: '', approvals: new Map() };
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
  };

  return {
    liveCount: () => lives.size,
    clientJoined() {
      clients++;
      for (const live of lives.values()) live.cancelIdle?.();
    },
    clientLeft() {
      clients--;
      for (const [sessionId, live] of lives) armIdle(sessionId, live);
    },

    agents: () => chatAgents(config).map(({ name, harness, model, command }) => ({ name, harness, model, found: binaryFound(command ?? harness) })),

    list: ({ archived = false }: { archived?: boolean }) => ({
      sessions: db.select().from(sessions).where(eq(sessions.archived, archived)).orderBy(desc(sessions.lastActiveAt)).all().map((found) => ({ ...summary(found), live: lives.has(found.id) })),
    }),

    async open({ agent, folder, options, worktree }: { agent: string; folder: string; options?: Record<string, string>; worktree?: { from: string; name?: string } }) {
      const chosen = chatAgents(config).find((candidate) => candidate.name === agent);
      if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${agent}"`);
      const real = checkFolder(folder, config.root);
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

    /** Opens a closed session again from its stored native id, folder and options; a live one is just attached to. */
    async resume({ sessionId }: { sessionId: string }) {
      const current = row(sessionId);
      const present = lives.get(sessionId);
      if (present !== undefined) return { session: summary(current), options: present.conversation.options };
      const chosen = chatAgents(config).find((candidate) => candidate.name === current.agent);
      if (chosen === undefined) throw new ChatRefused(`The agent "${current.agent}" of this session is not configured any more`);
      const runner = runners[chosen.harness];
      if (runner === undefined) throw new ChatRefused(`This host has no chat runner for ${chosen.harness}`);
      const folder = checkFolder(current.folder, config.root);
      // a session that never got a native id (nothing was said) has nothing to resume: it starts again, as it was opened
      const conversation = await openConversation(chosen, runner, { folder, options: current.options ?? {}, ...(current.nativeId !== null && { resume: current.nativeId }) });
      if (lives.has(sessionId)) {
        // another client resumed it while this one waited for the provider
        await conversation.close();
        return { session: summary(row(sessionId)), options: lives.get(sessionId)!.conversation.options };
      }
      attach(sessionId, conversation);
      return { session: summary(current), options: conversation.options };
    },

    send({ sessionId, text }: { sessionId: string; text: string }) {
      if (text.length > chatCaps.message) throw new ChatRefused(`That message has ${text.length} characters; the most a message can have is ${chatCaps.message}`);
      const current = row(sessionId);
      const live = lives.get(sessionId);
      if (live === undefined) throw new ChatRefused('This session is closed');
      if (live.state !== 'idle') throw new ChatRefused('The agent is still answering');
      if (current.title === null) db.update(sessions).set({ title: titleOf(text) }).where(eq(sessions.id, sessionId)).run();
      live.turn = { startedAt: clock.now(), toolCalls: 0 };
      store(sessionId, { kind: 'user', text });
      touch(sessionId, live, 'working');
      try {
        live.conversation.send(text);
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
        events: rows.map(({ id, at, kind, data }) => ({ id, at, kind, ...data })),
        cursor: rows.at(-1)?.id ?? after,
        session: summary(current),
        streaming: live?.streaming ?? '',
        approvals: [...(live?.approvals.values() ?? [])],
        options: live?.conversation.options ?? [],
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
      await settle(sessionId, 'delete');
      const { workspaceKind, worktreeBranch, worktreeFrom, worktreeBase, worktreePath } = row(sessionId);
      // The worktree goes first: one that cannot be removed stops the deletion and the session stays.
      if (workspaceKind === 'worktree') await deleteWorktree(git, { path: worktreePath!, branch: worktreeBranch!, from: worktreeFrom!, base: worktreeBase! });
      db.transaction((tx) => {
        tx.delete(chatEvents).where(eq(chatEvents.sessionId, sessionId)).run();
        tx.delete(chatTurns).where(eq(chatTurns.sessionId, sessionId)).run();
        tx.delete(sessions).where(eq(sessions.id, sessionId)).run();
      });
      return {};
    },

    /** What deleting these sessions would discard: for each one in a worktree, its uncommitted files and the commits that exist nowhere else. An unknown id refuses the whole request. */
    async deletePreview({ sessionIds }: { sessionIds: string[] }) {
      const found = sessionIds.map(row);
      // One session after another: a worktree reads two git processes, and the preview is a one-off, not a hot path.
      const previews = [];
      for (const { id, workspaceKind, worktreeBranch, worktreeFrom, worktreeBase, worktreePath } of found) {
        previews.push({
          sessionId: id,
          worktree: workspaceKind === 'worktree' ? { path: worktreePath!, branch: worktreeBranch!, ...(await previewWorktree(git, { path: worktreePath!, branch: worktreeBranch!, from: worktreeFrom!, base: worktreeBase! })) } : null,
        });
      }
      return { sessions: previews };
    },

    /** What a folder is as a git repository, for the person to choose how to work in it. */
    workspace: async ({ folder }: { folder: string }) => inspectFolder(git, checkFolder(folder, config.root)),

    /** Fetches `origin` of a folder and answers what it is after it. */
    fetch: async ({ folder }: { folder: string }) => fetchFolder(git, checkFolder(folder, config.root)),

    /** A free name for a worktree of a folder, from the StarCraft word lists. */
    suggestName: async ({ folder }: { folder: string }) => suggestName(git, checkFolder(folder, config.root)),

    /** Whether a typed worktree name is valid and free. */
    checkName: async ({ folder, name }: { folder: string; name: string }) => checkName(git, checkFolder(folder, config.root), name),

    /** Closes every live session: the host's stop. */
    async closeAll() {
      for (const sessionId of [...lives.keys()]) await close({ sessionId });
    },
  };
}

export type ChatSessions = ReturnType<typeof createSessions>;
