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
import { ChatRefused, type ChatConversation, type ChatEvent, type ChatOption, type ChatRunner } from './runner.ts';
import { chatEvents, chatTurns, sessions } from './schema.ts';
import { boundEvent, chatCaps, titleOf } from './transcript.ts';

const log = createScopedLogger('chat');

export const IDLE_CLOSE_MS = 60_000;

type Harness = (typeof sessions.$inferSelect)['harness'];
type State = (typeof sessions.$inferSelect)['state'];

export type SessionSummary = Omit<typeof sessions.$inferSelect, 'options' | 'pid' | 'pgid'>;

/** A session whose agent process runs: what is only true while it does. */
type Live = {
  conversation: ChatConversation;
  state: State;
  /** The text of the message being written, not stored until it ends. */
  streaming: string;
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
export function createSessions({ db, config, clock, runners, env, binaryFound, onLiveChange }: ChatSessionsDeps) {
  const lives = new Map<string, Live>();
  let clients = 0;

  const row = (sessionId: string) => {
    const found = db.select().from(sessions).where(eq(sessions.id, sessionId)).get();
    if (found === undefined) throw new ChatRefused('There is no such session');
    return found;
  };
  const summary = ({ options: _options, pid: _pid, pgid: _pgid, ...rest }: typeof sessions.$inferSelect): SessionSummary => rest;

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
    if (event.kind === 'assistant' || event.kind === 'turn_end') live.streaming = '';
    store(sessionId, event);
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
    db.update(sessions).set({ state: 'idle', pid: null, pgid: null }).where(eq(sessions.id, sessionId)).run();
    try {
      await live.conversation.close();
    } catch (error) {
      log.error('closing a conversation failed', error);
    }
    onLiveChange();
    return {};
  }

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
      sessions: db.select().from(sessions).where(eq(sessions.archived, archived)).orderBy(desc(sessions.lastActiveAt)).all().map(summary),
    }),

    async open({ agent, folder, options }: { agent: string; folder: string; options?: Record<string, string> }) {
      const chosen = chatAgents(config).find((candidate) => candidate.name === agent);
      if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${agent}"`);
      const real = checkFolder(folder, config.root);
      const runner = runners[chosen.harness];
      if (runner === undefined) throw new ChatRefused(`This host has no chat runner for ${chosen.harness}`);
      const chosenOptions = { ...(chosen.model && { model: chosen.model }), ...chosen.options, ...options };
      let conversation: ChatConversation;
      try {
        conversation = await runner.open({ folder: real, options: chosenOptions, command: chosen.command, env });
      } catch (error) {
        if (error instanceof ChatRefused) throw error;
        log.error('a chat runner failed to open', error);
        throw new ChatRefused(`${chosen.name} could not be started`);
      }
      try {
        for (const [id, value] of Object.entries(chosenOptions)) checkOption(conversation.options, id, value);
      } catch (error) {
        await conversation.close().catch((closing) => log.error('closing a refused conversation failed', closing));
        throw error;
      }
      const now = clock.now();
      const created = db
        .insert(sessions)
        .values({ id: randomUUID(), agent: chosen.name, harness: chosen.harness, folder: real, options: chosenOptions, nativeId: conversation.nativeId ?? null, createdAt: now, lastActiveAt: now })
        .returning()
        .get();
      const live: Live = { conversation, state: 'idle', streaming: '' };
      lives.set(created.id, live);
      conversation.onEvent((event) => {
        try {
          onEvent(created.id, live, event);
        } catch (error) {
          log.error('a chat event could not be handled', error);
        }
      });
      armIdle(created.id, live);
      onLiveChange();
      return { session: summary(created), options: conversation.options };
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
        options: live?.conversation.options ?? [],
      };
    },

    close,

    /** Closes every live session: the host's stop. */
    async closeAll() {
      for (const sessionId of [...lives.keys()]) await close({ sessionId });
    },
  };
}

export type ChatSessions = ReturnType<typeof createSessions>;
