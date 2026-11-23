import { accessSync, constants, existsSync, realpathSync, rmSync, statSync } from 'node:fs';
import { basename, sep } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash, randomUUID } from 'node:crypto';
import { and, asc, count, desc, eq, gt, inArray, isNotNull, isNull, lt, ne, sql } from 'drizzle-orm';
import { createScopedLogger } from '@ashulab/universal-logger';
import { carrierHome, expandHome } from '../config/places.ts';
import { updateProjectsFile, readProjectsFile } from '../config/projects.ts';
import { type ChatAgents, chatAccount, readAccounts } from './account.ts';
import { claimAttachments, releaseAttachments, sessionFolder } from './attachments.ts';
import type { ChatAgent, ChatSettings, WorktreeCleanup } from './config.ts';
import { resolveBinary } from '../harnesses/common.ts';
import type { Clock } from '../orchestration/clock.ts';
import type { ChatDb } from './db.ts';
import { checkFolder } from './folder.ts';
import { buildHandoff } from './handoff.ts';
import { realMachine, type Machine } from '../doctor/detect.ts';
import { createHealth, realProbes, type HealthProbes } from './health.ts';
import { childOptions, delegationRefusal, isScaleHarness, type Level, levelOf } from './levels.ts';
import type { ChildReport, McpSessionRegistry } from './mcp.ts';
import { createProviders } from './providers.ts';
import type { Git } from './git.ts';
import { type ActionWhen, newProjectKind, type Plan, type Step, type StepEvent } from './plan.ts';
import { realShell, type Shell } from './shell.ts';
import { redact } from '../logging/redact.ts';
import { ChatRefused, type BackgroundTask, type ChatChoice, type ChatCommand, type ChatConversation, type ChatEvent, type ChatOption, type ChatQuestion, type ChatRunner } from './runner.ts';
import { clean } from '../execution/events.ts';
import { chatEvents, chatTurns, sessions } from './schema.ts';
import { noTextGenerator, TEXT_GENERATOR_LIMIT_MS, TextGeneratorFailed, type TextGenerator } from './text-generator.ts';
import { titleSystemMessage, titleText } from './title-prompt.ts';
import { boundEvent, chatCaps, previewOf, titleOf } from './transcript.ts';
import { checkName, checkWorktreeClash, samePath, suggestName } from './names.ts';
import { createProject, projectFolder, type createProjects } from './projects.ts';
import type { PullRequests } from './pull-requests.ts';
import { createSessionData } from './session-data.ts';
import { githubWorkOf } from './shell-effects.ts';
import { clearWorktree, createWorktree, deleteWorktree, folderBytes, headDetached, hiddenWork, isWorktreeFolder, listWorktrees, previewMain, previewWorktree, REMOVE_TIMEOUT_MS, removeWorktree, restoreWorktree } from './worktree.ts';
import { worktreesDir } from './names.ts';
import { checkout, FETCH_FRESH_MS, fetchFolder, inspectFolder } from './workspace.ts';

const log = createScopedLogger('chat');

const real = (path: string) => (existsSync(path) ? realpathSync(path) : path);

const noPullRequests: PullRequests = { find: async () => null, states: async () => new Map() };

/** An idle session that no request has named for this long is closed: its agent, with every MCP server the person has, holds most of a gigabyte. */
export const IDLE_CLOSE_MS = 10 * 60_000;
/** The children of one session that may work or wait for an approval at the same time ([ADR 0033](../../docs/adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md)). */
const MAX_RUNNING_CHILDREN = 4;
/** How much of a done child's last message `delegate_wait` answers. */
const CHILD_MESSAGE = 4000;
/** How many of the approvals a child waits for, and how much of each one's argument, `delegate_wait` says. */
const CHILD_APPROVALS = 4;
const CHILD_APPROVAL_ARG = 500;
/** `text` of at most `max` characters, ending in an ellipsis when it was cut, and never in the middle of a character. */
const cut = (text: string, max: number) => {
  const characters = [...text];
  return characters.length > max ? `${characters.slice(0, max - 1).join('')}…` : text;
};
/** How long a session whose last subagent just ended waits for the turn the SDK opens by itself (it follows at once) before it is idle. */
export const FOLLOW_UP_MS = 3_000;

const DAY = 86_400_000;
/** The lifecycle's ages (ADR 0019) and where a new worktree starts (ADR 0037), as `chat.json` gives them. */
export type LiveSettings = Pick<ChatSettings, 'archiveAfterDays' | 'deleteAfterDays'> & Partial<Pick<ChatSettings, 'worktreeCleanup' | 'worktreeStart' | 'idleCloseMinutes'>>;
const idleFor = (row: { state: State; lastActiveAt: number }, live: boolean, now: number, days: number | 'never') => days !== 'never' && row.state === 'idle' && !live && now - row.lastActiveAt >= days * DAY;

type Harness = (typeof sessions.$inferSelect)['harness'];
type State = (typeof sessions.$inferSelect)['state'];
export type TitleSource = NonNullable<(typeof sessions.$inferSelect)['titleSource']>;

/** Where a session works: the folder it was opened in, or a worktree made for it from that base folder. */
export type SessionWorkspace = { kind: 'folder' } | { kind: 'worktree'; branch: string; from: string; base: string; path: string };

/** One worktree of a project's page: the session that made it (or none) and its state, see `projectWorktrees`. */
export type ProjectWorktree = { path: string; branch: string | null; session: { id: string; title: string | null } | null; lastActiveAt: number; state: 'sessionOpen' | 'uncommitted' | 'merged' | 'notPushed' | 'clean' };
/** What the project's own folder holds that would be lost with it: uncommitted changes, commits on its branch that no other branch or remote holds, else clean. */
export type ProjectWorktrees = { main: { path: string; branch: string | null; state: 'uncommitted' | 'notPushed' | 'clean' }; worktrees: ProjectWorktree[] };

/** A child session as its parent's summary lists it; `level` is the permission level it runs at, and `needsPerson` says that it waits for an approval or a question. */
export type ChildSummary = { id: string; agent: string; harness: Harness; state: State; level: Level | null; needsPerson: boolean };

export type SessionSummary = Omit<typeof sessions.$inferSelect, 'titleSource' | 'keptAt' | 'prRepo' | 'prNumber' | 'prUrl' | 'prState' | 'prChecks' | 'prCheckedAt' | 'options' | 'pid' | 'pgid' | 'command' | 'plan' | 'workspaceKind' | 'worktreeBranch' | 'worktreeFrom' | 'worktreeBase' | 'worktreePath' | 'delegationRequestId'> & {
  workspace: SessionWorkspace;
  /** The sessions that this one started by delegating, oldest first. */
  children: ChildSummary[];
  /** `running` while the host prepares the session, `failed` when a step failed and the plan is kept, null otherwise. */
  preparation: 'running' | 'failed' | null;
};

export type PendingApproval = { approvalId: string; tool: string; arg?: string; choices: ChatChoice[]; questions?: ChatQuestion[] };

/** A session whose agent process runs: what is only true while it does. */

/** A turn in progress: when it began, its own tool calls, whether anything ran in it (its subagents' too), the shell commands still running by call id, and the ones that ended well. */
type Turn = { startedAt: number; toolCalls: number; acted: boolean; shell: Map<string, string>; commands: string[] };
type Live = {
  conversation: ChatConversation;
  state: State;
  /** The text of the message being written, not stored until it ends. */
  streaming: string;
  /** The approvals asked and not yet answered, as they are stored (redacted and bounded). */
  approvals: Map<string, PendingApproval>;
  turn?: Turn;
  /** The subagents running, by task id: from their `started` until `completed`, `failed` or `stopped`. */
  tasks: Set<string>;
  /** True while the `message` step of a preparation waits for the agent's first answer. */
  awaitingAnswer?: boolean;
  cancelIdle?: () => void;
  /** What the agent has running in the background after its turn ended, each with when the host first saw it (ms); kept in memory, as the agent says it, and gone with the conversation. */
  background: (BackgroundTask & { startedAt: number })[];
  /** Ends the wait for the turn the SDK opens after the last subagent ended (`FOLLOW_UP_MS`). */
  cancelFollowUp?: () => void;
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
  /** What runs a project's actions; the machine's own `sh` unless a test replaces it. */
  shell?: Shell;
  /** What brings a repository onto the Mac, for a plan that clones one. */
  projects: Pick<ReturnType<typeof createProjects>, 'cloneRepo' | 'repoFolder' | 'stepOf'>;
  /** Whether an agent's binary is there. */
  binaryFound: (command: string) => boolean;
  /** What the `health` request runs; the machine's own tools unless a test replaces it. */
  probes?: HealthProbes;
  /** What the `providers` request asks of the machine; the real one unless a test replaces it. */
  machine?: Machine;
  /** Where a session's pull request is read from; without it a row has none unless it was found before. */
  pulls?: PullRequests;
  /** The lifecycle's ages now: `list` says from them when the clock will delete each archived session. */
  ages: () => LiveSettings;
  /** How long an idle session that no request names stays open, asked each time one is armed; `IDLE_CLOSE_MS` when none is given. */
  idleCloseMs?: () => number;
  /** Called when a session becomes or stops being live, so the host can start or cancel its own countdown. */
  onLiveChange: () => void;
  /** What writes a session's title (ADR 0038); a host that is given none refuses the request in words. */
  textGenerator?: TextGenerator;
  /** The chat MCP: the registry that issues each conversation's token and the URL of the endpoint, which is undefined when the host could not start it. Without this a host has no MCP and says nothing of it. */
  mcp?: { registry: McpSessionRegistry; url: () => string | undefined; /** Every tool of the chat MCP, by name, which the adapters are told when a conversation opens. */ tools: string[] };
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
export function createSessions({ db, agents, clock, runners, env, git, shell = realShell, projects, binaryFound, probes = realProbes, machine = realMachine, ages, idleCloseMs = () => IDLE_CLOSE_MS, onLiveChange, mcp, pulls = noPullRequests, textGenerator = noTextGenerator }: ChatSessionsDeps) {
  const data = createSessionData({ db, git, pulls, clock });
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
  // Children whose row exists and whose conversation is still opening, until each is attached or discarded: what a repeated call waits on, and what archive and delete refuse over.
  const opening = new Map<string, Promise<void>>();
  // Sessions whose worktree folder the clock's cleanup is reading or removing, until it is done: an agent about to open in the folder waits for it.
  const clearing = new Map<string, Promise<void>>();
  const notSwitching = (sessionId: string) => {
    if (switching.has(sessionId)) throw new ChatRefused('This session is switching to another agent; try again in a moment');
  };

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
  /** A session aged with its children as one (ADR 0033): the latest activity of the family, live when any member is. */
  const familyClock = (found: { id: string; lastActiveAt: number }) => {
    const kids = db.select({ id: sessions.id, lastActiveAt: sessions.lastActiveAt }).from(sessions).where(eq(sessions.parentSessionId, found.id)).all();
    return { lastActiveAt: Math.max(found.lastActiveAt, ...kids.map((kid) => kid.lastActiveAt)), live: [found, ...kids].some((member) => lives.has(member.id) || opening.has(member.id)) };
  };
  const worktreeOf = (found: typeof sessions.$inferSelect) => ({ path: found.worktreePath!, branch: found.worktreeBranch!, from: found.worktreeFrom!, base: found.worktreeBase! });

  /** The folder a session works in, checked; a worktree the cleanup removed comes back on its kept branch first, with its actions (`restore`). */
  const folderOf = async (found: typeof sessions.$inferSelect) => {
    await clearing.get(found.id)?.catch(() => undefined); // its failure is the clock's to log; what it left is looked at below
    if (found.workspaceKind === 'worktree') await restore(found);
    return checkFolder(found.folder, carrierHome());
  };
  /**
   * Where a restore that stopped began, as the id just before its first event: the steps that end the session's log, the `action` ones and the `worktree` marker a restore opens with
   * (`bringBack`), when the last of them is not done. The original preparation ends with the agent's steps, and a restore that finished ends with a done action or marker, so a log
   * that ends with a step running or failed is a restore to go on with. The run begins at the latest marker, so restores one after another are not taken for one.
   */
  const unfinishedRestore = (sessionId: string) => {
    const steps = db.select({ id: chatEvents.id, data: chatEvents.data }).from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'step'))).orderBy(desc(chatEvents.id)).all();
    const run: typeof steps = [];
    for (const event of steps) {
      if (event.data.step !== 'action' && event.data.step !== 'worktree') break;
      run.push(event);
      if (event.data.step === 'worktree' && event.data.status === 'running') break; // where the marker began
    }
    return run.length > 0 && run[0]!.data.status !== 'done' ? run.at(-1)!.id - 1 : undefined;
  };
  /**
   * Makes the folder of a worktree session ready, once at a time: callers that come in while it runs share it, and the folder is not touched by anything else meanwhile
   * (`restoring`: the clock's cleanup, removing a worktree, delete and archive all refuse). A folder that is there is only checked, unless the last restore stopped.
   * ponytail: the actions of a stopped restore go on from the one that stopped (the folder stays, its finished actions are skipped as in Try again); a restore that stopped and a
   * cleanup that took the folder after it start over, as ADR 0035 says a folder that comes back does. Edit the actions so none is left to run and the log still reads as stopped, harmlessly.
   */
  const restore = async (found: typeof sessions.$inferSelect): Promise<void> => {
    const running = restoring.get(found.id);
    if (running !== undefined) return running.done;
    const there = existsSync(found.worktreePath!);
    const unfinished = there ? unfinishedRestore(found.id) : undefined;
    if (there && unfinished === undefined) return restoreWorktree(git, worktreeOf(found)); // checks the record only
    if (deleting.has(found.id)) throw new ChatRefused('This session is being deleted');
    const entry = { abort: new AbortController(), done: Promise.resolve() };
    restoring.set(found.id, entry);
    entry.done = bringBack(found, entry.abort.signal, unfinished).finally(() => {
      restoring.delete(found.id);
      progress.delete(found.id);
    });
    return entry.done;
  };
  /**
   * The new-worktree actions of the project in a folder just brought back (ADR 0039), as the `action` steps of a preparation: the same progress and failure, and Cancel aborts the
   * one that runs. When one stops the session or the person cancels, the folder stays and the open is refused; the next open goes on from the action that stopped.
   * The folder coming back is the `worktree` step that opens a restore, so the app has a row to show before the first action; a restore that goes on from one that stopped (`unfinished`)
   * finds its folder and keeps the marker of the first try. `after` is where this restore begins in the log, so what an earlier restore finished is not taken for this one's.
   */
  const bringBack = async (found: typeof sessions.$inferSelect, signal: AbortSignal, unfinished: number | undefined) => {
    if (unfinished === undefined) {
      stepEvent(found.id, 'worktree', 'running');
      try {
        await restoreWorktree(git, worktreeOf(found));
      } catch (error) {
        if (error instanceof ChatRefused === false) log.error('bringing back a worktree failed', error);
        failStep(found.id, 'worktree', error instanceof ChatRefused ? error.message : 'The worktree could not be brought back');
        throw error;
      }
      stepEvent(found.id, 'worktree', 'done');
    }
    const file = readProjectsFile();
    if (file.ok) told.delete(found.id); // a notice that says the file is invalid is told again only once it was valid in between
    const after = unfinished ?? db.select({ id: chatEvents.id }).from(chatEvents).where(eq(chatEvents.sessionId, found.id)).orderBy(desc(chatEvents.id)).limit(1).get()?.id ?? 0;
    if (await runActions(found.id, file, found.worktreeBase!, 'newWorktree', found.worktreePath!, signal, after)) return;
    const stopped = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, found.id), eq(chatEvents.kind, 'step'), gt(chatEvents.id, after))).orderBy(desc(chatEvents.id)).limit(1).get()?.data;
    throw new ChatRefused(signal.aborted ? 'Setting up the worktree was cancelled; open the session again to go on from where it stopped' : `${stopped?.detail ?? 'An action failed'}. Open the session again to go on from that action`);
  };

  /** The cleanup of `chat.json`'s `worktreeCleanup`: removes the folder of an idle session's worktree whose PR is merged or that is archived and has had no activity for `afterInactiveDays`, never one with uncommitted work, and keeps its branch. */
  const cleanWorktrees = async ({ afterPrMerged, afterInactiveDays }: WorktreeCleanup, now: number) => {
    if (afterPrMerged === false && afterInactiveDays === 'never') return;
    for (const found of db.select().from(sessions).where(and(eq(sessions.workspaceKind, 'worktree'), isNull(sessions.parentSessionId))).all()) {
      if (closed) return;
      if (switching.has(found.id) || deleting.has(found.id) || restoring.has(found.id) || existsSync(found.worktreePath!) === false) continue;
      /** Whether the row is still due: merged, or archived and idle, and not open. Asked again after git is read, as the person may have come back meanwhile. */
      const dueNow = (row: typeof found) => {
        const { lastActiveAt, live } = familyClock(row);
        return row.state === 'idle' && live === false && ((afterPrMerged && row.prState === 'merged') || (row.archived && idleFor({ state: row.state, lastActiveAt }, live, now, afterInactiveDays)));
      };
      if (dueNow(found) === false) continue;
      const clear = async () => {
        if (isWorktreeFolder(found.worktreePath!) === false) {
          log.warn('kept a worktree folder git cannot read (it has no .git, a removal killed halfway leaves that); Carrier does not delete it, see docs/troubleshooting.md', { sessionId: found.id });
          return;
        }
        const [{ dirty }, detached] = await Promise.all([previewWorktree(git, worktreeOf(found), [found.worktreeBranch!]), headDetached(git, worktreeOf(found))]);
        const hidden = dirty > 0 || detached ? null : await hiddenWork(git, worktreeOf(found));
        if (dirty > 0 || detached || hidden !== null) {
          log.info(detached ? 'kept a worktree whose HEAD is detached' : dirty > 0 ? 'kept a worktree with uncommitted work' : `kept a worktree that holds ${hidden}`, { sessionId: found.id, dirty });
          return;
        }
        const row = db.select().from(sessions).where(eq(sessions.id, found.id)).get();
        if (closed || row === undefined || switching.has(found.id) || deleting.has(found.id) || restoring.has(found.id) || dueNow(row) === false) return; // the host stopped or the session was taken up while git read it
        await clearWorktree(git, worktreeOf(row), REMOVE_TIMEOUT_MS);
        log.info('removed the folder of a worktree, its branch is kept', { sessionId: found.id, branch: found.worktreeBranch });
      };
      const cleared = clear();
      clearing.set(found.id, cleared);
      try {
        await cleared;
      } catch (error) {
        log.error('the clock could not clean up a worktree; the next pass tries again', error);
      } finally {
        clearing.delete(found.id);
      }
    }
  };
  /** What `projectWorktrees` reads of each worktree, with what removing it needs: its session's row and whether it is open. */
  type Entry = { worktree: ProjectWorktree; found: typeof sessions.$inferSelect | undefined; live: boolean; dirty: number };
  const readProjectWorktrees = async (folder: string) => {
    const base = checkFolder(folder, carrierHome());
    const [main, ...linked] = await listWorktrees(git, base);
    const root = real(worktreesDir()) + sep;
    const bySession = new Map(db.select().from(sessions).where(and(eq(sessions.workspaceKind, 'worktree'), isNull(sessions.parentSessionId))).all().map((found) => [real(found.worktreePath!), found]));
    const entries: Entry[] = [];
    // one worktree after another: each reads two git processes, and this is one project's page opening
    for (const { path, branch } of linked) {
      if (existsSync(path) === false || real(path).startsWith(root) === false) continue;
      const found = bySession.get(real(path));
      const family = found === undefined ? undefined : familyClock(found);
      // a detached HEAD has no branch to hold commits, so only its files count
      const { dirty, unpushed } = await previewWorktree(git, { path, branch: branch ?? '', from: '', base }, branch === null ? [] : [branch]);
      const state = family?.live ? 'sessionOpen' : dirty > 0 ? 'uncommitted' : found?.prState === 'merged' ? 'merged' : unpushed > 0 ? 'notPushed' : 'clean';
      const worktree: ProjectWorktree = { path, branch, session: found === undefined ? null : { id: found.id, title: found.title }, lastActiveAt: family?.lastActiveAt ?? statSync(path).mtimeMs, state };
      entries.push({ worktree, found, live: family?.live === true, dirty });
    }
    return { base, main: { path: base, branch: main?.branch ?? null }, entries };
  };
  /** Why a worktree cannot be removed now, or null. */
  const blockOf = ({ live, dirty, found }: Entry) =>
    live || (found !== undefined && (switching.has(found.id) || deleting.has(found.id) || restoring.has(found.id))) ? 'Its session is open' : dirty > 0 ? 'It has uncommitted changes' : null;
  /** Removes the folder of one worktree, as the clock's cleanup does: its session waits for it before opening the folder, and it is checked again just before git is asked. */
  const removeProjectEntry = async (base: string, entry: Entry) => {
    const { worktree, found } = entry;
    const reason = blockOf(entry);
    if (reason !== null) throw new ChatRefused(reason);
    const made = { path: worktree.path, branch: worktree.branch ?? '', from: '', base };
    const clear = async () => {
      // taken up while git read it
      if (found !== undefined && (familyClock(found).live || switching.has(found.id) || deleting.has(found.id) || restoring.has(found.id))) throw new ChatRefused('Its session is open');
      await clearWorktree(git, made);
      log.info('removed the folder of a worktree by request, its branch is kept', { branch: worktree.branch });
    };
    const cleared = clear();
    if (found !== undefined) clearing.set(found.id, cleared);
    try {
      await cleared;
    } finally {
      if (found !== undefined) clearing.delete(found.id);
    }
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
  const summary = ({ titleSource: _titleSource, keptAt: _keptAt, prRepo: _prRepo, prNumber: _prNumber, prUrl: _prUrl, prState: _prState, prChecks: _prChecks, prCheckedAt: _prCheckedAt, options: _options, pid: _pid, pgid: _pgid, command: _command, delegationRequestId: _delegationRequestId, plan, workspaceKind, worktreeBranch, worktreeFrom, worktreeBase, worktreePath, ...rest }: typeof sessions.$inferSelect): SessionSummary => ({
    ...rest,
    children: childrenOf(rest.id),
    preparation: rest.state === 'preparing' || restoring.has(rest.id) ? 'running' : plan === null ? null : 'failed',
    workspace: workspaceKind === 'worktree' ? { kind: 'worktree', branch: worktreeBranch!, from: worktreeFrom!, base: worktreeBase!, path: worktreePath! } : { kind: 'folder' },
  });

  /** What a list says of how a session went: the words its agent last wrote, not a subagent's (one line, already redacted as stored), the turns that finished and the model of the last. */
  const activity = (sessionId: string) => {
    const message = db.select({ data: chatEvents.data }).from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'assistant'), sql`json_extract(${chatEvents.data}, '$.parentCallId') is null`)).orderBy(desc(chatEvents.id)).limit(1).get();
    const turns = db.select({ n: count() }).from(chatTurns).where(eq(chatTurns.sessionId, sessionId)).get()?.n ?? 0;
    const last = db.select({ model: chatTurns.model }).from(chatTurns).where(eq(chatTurns.sessionId, sessionId)).orderBy(desc(chatTurns.id)).limit(1).get();
    const text = message?.data.text;
    return { lastMessage: typeof text === 'string' && text.trim() !== '' ? previewOf(text) : null, turns, model: last?.model ?? null };
  };

  /** The first message of a session, as stored (redacted and bounded): what its title is written from and what the legacy rule compares. */
  const firstMessage = (sessionId: string) => {
    const found = db.select({ id: chatEvents.id, data: chatEvents.data }).from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'user'))).orderBy(asc(chatEvents.id)).limit(1).get();
    return found === undefined ? undefined : { id: found.id, text: typeof found.data.text === 'string' ? found.data.text : '' };
  };
  /** The first reply of the session's own agent (not a subagent's) after that message, when it has one. */
  const firstReply = (sessionId: string, after: number) => {
    const found = db.select({ data: chatEvents.data }).from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'assistant'), gt(chatEvents.id, after), sql`json_extract(${chatEvents.data}, '$.parentCallId') is null`)).orderBy(asc(chatEvents.id)).limit(1).get();
    const text = found?.data.text;
    return typeof text === 'string' && text.trim() !== '' ? text : undefined;
  };
  /** Where a row's title came from. A row from before the column has none: a title equal to the first line of its first message is a first-line one, any other was set by the person. */
  const titleSourceOf = (found: typeof sessions.$inferSelect): TitleSource | null => {
    if (found.titleSource !== null || found.title === null) return found.titleSource;
    const first = firstMessage(found.id);
    return first !== undefined && found.title === titleOf(first.text) ? 'first_line' : 'renamed';
  };
  // One call to the generator at a time: two sessions that ask together do not make a server load a model twice. A call that passes the limit is a failure, whatever the generator does after.
  let generating: Promise<unknown> = Promise.resolve();
  const generate = (input: { system: string; text: string }) => {
    const call = () =>
      new Promise<string>((resolve, reject) => {
        const cancel = clock.after(TEXT_GENERATOR_LIMIT_MS, async () => reject(new TextGeneratorFailed(`the text generator did not answer within ${TEXT_GENERATOR_LIMIT_MS / 1000} seconds`)));
        textGenerator.generate(input).then(resolve, reject).finally(cancel);
      });
    const run = generating.then(call, call);
    generating = run.catch(() => {});
    return run;
  };
  // Sessions whose title is being written in the background, so a second turn ending meanwhile does not ask twice.
  const titling = new Set<string>();
  /** Generates a cleaned title from `message` and `reply` (when there is one), logging and rethrowing on failure. */
  const generateTitle = async (sessionId: string, message: string, reply?: string) => {
    try {
      const title = titleOf(await generate({ system: titleSystemMessage, text: titleText(message, reply) }));
      if (title === '') throw new TextGeneratorFailed('the text generator answered with no text');
      return title;
    } catch (error) {
      log.error('the text generator could not write a title', error, { sessionId });
      throw error;
    }
  };
  /**
   * Titles a session in the background after a turn ends well: never a child, never over a renamed or already generated title,
   * never when there is no reply yet, and never failing or delaying the session.
   */
  const autoTitle = async (sessionId: string) => {
    if (closed || titling.has(sessionId)) return;
    const found = db.select().from(sessions).where(eq(sessions.id, sessionId)).get();
    if (found === undefined || found.parentSessionId !== null || titleSourceOf(found) !== 'first_line') return;
    const first = firstMessage(sessionId);
    if (first === undefined || first.text.trim() === '') return;
    const reply = firstReply(sessionId, first.id);
    if (reply === undefined) return;
    titling.add(sessionId);
    try {
      const title = await generateTitle(sessionId, first.text, reply);
      if (closed) return;
      const current = db.select().from(sessions).where(eq(sessions.id, sessionId)).get();
      if (current === undefined || current.parentSessionId !== null || titleSourceOf(current) !== 'first_line') return;
      db.update(sessions).set({ title, titleSource: 'generated' }).where(eq(sessions.id, sessionId)).run();
    } catch {
      // already logged in generateTitle; the title stays the first line and the next turn tries again
    } finally {
      titling.delete(sessionId);
    }
  };

  // Worktrees are made one at a time: what a request checked (a free name) is still true when git adds.
  let making: Promise<unknown> = Promise.resolve();
  const exclusive = <T>(work: () => Promise<T>): Promise<T> => {
    const run = making.then(work, work);
    making = run.catch(() => {});
    return run;
  };

  // An idle session that no request has named for IDLE_CLOSE_MS is closed (reading its events, sending to it or changing its options names it; listing the
  // sessions does not); working or waiting ones are kept, and so is one that waits for something it started in the background.
  const armIdle = (sessionId: string, live: Live) => {
    live.cancelIdle?.();
    live.cancelIdle = live.state === 'idle' && live.background.length === 0 && !switching.has(sessionId)
      ? clock.after(idleCloseMs(), async () => {
          log.info('closing a session that no request had named', { sessionId });
          await close({ sessionId });
        })
      : undefined;
  };
  /** A request named this session: a live one that is idle starts its idle time again. */
  const renew = (sessionId: string) => {
    const live = lives.get(sessionId);
    if (live !== undefined) armIdle(sessionId, live);
  };
  /** What `delegate_wait` is waiting on: called whenever a session changes state. */
  const waiters = new Set<() => void>();
  const notifyWaiters = () => [...waiters].forEach((wake) => wake());
  const touch = (sessionId: string, live: Live, state: State = live.state) => {
    live.state = state;
    db.update(sessions).set({ state, lastActiveAt: clock.now(), ...(live.conversation.nativeId !== undefined && { nativeId: live.conversation.nativeId }) }).where(eq(sessions.id, sessionId)).run();
    armIdle(sessionId, live);
    notifyWaiters();
  };
  const store = (sessionId: string, event: ChatEvent | StepEvent) => {
    const data = boundEvent(event);
    if (data !== undefined) db.insert(chatEvents).values({ sessionId, at: clock.now(), kind: event.kind, data }).run();
  };

  // Sessions whose steps run in the background and are not live yet: the host is not idle while one does. `abort` stops the running step, `done` ends when the steps stopped.
  const preparing = new Map<string, { abort: AbortController; done: Promise<void> }>();
  // The latest line of git's progress for the clone of a session that is cloning: shown by `events`, never stored.
  const progress = new Map<string, string>();
  // Sessions whose worktree folder is coming back and whose actions run: `abort` stops the one that runs, `done` ends when the restore has unwound, which whatever touches the folder waits for or refuses over.
  const restoring = new Map<string, { abort: AbortController; done: Promise<void> }>();
  // Sessions told that `projects.json` did not match, so a retry, a second moment or another restore does not say it again: a preparation forgets it when it ends, a restore once the file matched.
  const told = new Set<string>();
  const stepEvent = (sessionId: string, step: Step, status: StepEvent['status'], detail?: string, action?: Pick<StepEvent, 'action' | 'when'>) => store(sessionId, { kind: 'step', step, status, ...(detail !== undefined && { detail }), ...action });
  /** How the last event of a step left it, undefined when the step never ran. */
  const lastStatus = (sessionId: string, step: Step) => {
    const events = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'step'))).orderBy(desc(chatEvents.id)).all();
    return events.find((event) => event.data.step === step)?.data.status as StepEvent['status'] | undefined;
  };
  /** Stops a preparation at a step: the session is idle, the plan stays and the event says why. */
  const failStep = (sessionId: string, step: Step, detail: string, action?: Pick<StepEvent, 'action' | 'when'>) => {
    stepEvent(sessionId, step, 'failed', detail, action);
    db.update(sessions).set({ state: 'idle', lastActiveAt: clock.now() }).where(eq(sessions.id, sessionId)).run();
  };
  // A host that stopped mid-preparation left sessions whose last step is still running: it comes back failed as interrupted.
  for (const { id: sessionId } of db.select({ id: sessions.id }).from(sessions).where(isNotNull(sessions.plan)).all()) {
    const last = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'step'))).orderBy(desc(chatEvents.id)).limit(1).get();
    if (last?.data.status === 'running') stepEvent(sessionId, last.data.step as Step, 'failed', 'Carrier stopped while this step was running');
    db.update(sessions).set({ state: 'idle' }).where(and(eq(sessions.id, sessionId), eq(sessions.state, 'preparing'))).run();
  }

  /** A turn that begins: what the agent runs in it is kept, to know at its end what to read again (`afterTurn`). */
  const openTurn = (): Turn => ({ startedAt: clock.now(), toolCalls: 0, acted: false, shell: new Map(), commands: [] });

  const onEvent = (sessionId: string, live: Live, event: ChatEvent) => {
    // What the agent waits for in the background is the state of the session, not something said in it: it is kept as it is and never stored.
    if (event.kind === 'background') {
      // a task that was there keeps the time it began; one that is new begins now
      live.background = event.tasks.map((task) => ({ id: task.id, kind: task.kind, description: clean(task.description, chatCaps.arg), startedAt: live.background.find((known) => known.id === task.id)?.startedAt ?? clock.now() }));
      armIdle(sessionId, live);
      onLiveChange();
      return;
    }
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
    // The agent can begin a turn nobody asked for: the SDK wakes it when something it ran in the background ends. It is working from its first word,
    // and the `turn_end` the adapter says when it finishes closes it as any other. Only a live conversation does: a word that comes late from one
    // the host already closed is not a turn.
    if (live.turn === undefined && live.state === 'idle' && lives.get(sessionId) === live && ['delta', 'assistant', 'reasoning', 'tool_start', 'approval'].includes(event.kind)) {
      live.turn = openTurn();
      touch(sessionId, live, 'working');
    }
    if (event.kind === 'delta') return void (live.streaming += event.text);
    if (event.kind === 'turn_start') {
      // the SDK answers a subagent that ended after the turn did: no message opened this turn, so open it here, or its `turn_end` is dropped and the session shows idle while it runs
      live.cancelFollowUp?.();
      live.turn ??= openTurn();
      return touch(sessionId, live, 'working');
    }
    if (event.kind === 'turn_end' && live.turn === undefined) return; // a turn already recorded (an interrupt, then the adapter's own end)
    if (event.kind === 'assistant' || event.kind === 'turn_end') live.streaming = '';
    store(sessionId, event);
    if (event.kind === 'approval') live.approvals.set(event.approvalId, boundEvent(event) as PendingApproval);
    if (event.kind === 'approval_answered') {
      live.approvals.delete(event.approvalId);
    }
    if (event.kind === 'turn_end') {
      live.approvals.clear(); // an interrupted turn drops what it was waiting for
    }
    if (event.kind === 'option') {
      const { options } = row(sessionId);
      db.update(sessions).set({ options: { ...options, [event.id]: event.value } }).where(eq(sessions.id, sessionId)).run();
    }
    if (event.kind === 'task' && event.state === 'started') live.tasks.add(event.taskId);
    const lastEnded = event.kind === 'task' && ['completed', 'failed', 'stopped'].includes(event.state) && live.tasks.delete(event.taskId) && live.tasks.size === 0 && live.turn === undefined;
    if (event.kind === 'tool_start' && live.turn && event.parentCallId === undefined) live.turn.toolCalls++; // the turn's own calls, not its subagents'
    if (live.turn !== undefined && (event.kind === 'tool_start' || event.kind === 'tool_end')) {
      // what ended well and was a shell command (Claude's `Bash`, Codex's `command`), whoever ran it: a subagent works in the same folder
      if (event.kind === 'tool_start') {
        live.turn.acted = true;
        if ((event.tool === 'Bash' || event.tool === 'command') && event.arg !== undefined) live.turn.shell.set(event.callId, event.arg);
      } else {
        const command = live.turn.shell.get(event.callId);
        live.turn.shell.delete(event.callId);
        if (command !== undefined && event.status === 'ok') live.turn.commands.push(command);
      }
    }
    if (event.kind === 'turn_end') {
      const startedAt = live.turn?.startedAt ?? clock.now();
      const { harness, agent } = row(sessionId);
      db.insert(chatTurns).values({ sessionId, startedAt, harness, agent, nativeId: live.conversation.nativeId ?? null, model: event.model ?? null, outcome: event.outcome, durationMs: clock.now() - startedAt, toolCalls: live.turn?.toolCalls ?? 0, usage: event.usage ?? null }).run();
      const ran = live.turn;
      live.turn = undefined;
      // what the turn ran says what to read again; a turn with no record of it reads everything
      void data.afterTurn(sessionId, ran === undefined ? undefined : { acted: ran.acted, github: githubWorkOf(ran.commands) });
      if (event.outcome === 'ok') void autoTitle(sessionId);
    }
    // The SDK runs subagents in the background, so a turn can end before them: the session is idle only when the turn is over and no task runs.
    const busy = live.turn !== undefined || live.tasks.size > 0;
    // The last subagent ending after the turn did is followed by a turn the SDK opens itself (`turn_start`): the session stays working until that turn ends, and goes idle if the SDK opens none.
    if (lastEnded) {
      live.cancelFollowUp?.();
      live.cancelFollowUp = clock.after(FOLLOW_UP_MS, async () => {
        live.cancelFollowUp = undefined;
        if (lives.get(sessionId) === live && live.turn === undefined && live.tasks.size === 0 && live.state === 'working') touch(sessionId, live, 'idle');
      });
    }
    const next = event.kind === 'turn_end' ? (busy ? 'working' : 'idle') : event.kind === 'task' ? (busy || lastEnded ? (live.state === 'idle' ? 'working' : live.state) : 'idle') : live.state;
    touch(sessionId, live, event.kind === 'approval' ? 'waiting_approval' : event.kind === 'approval_answered' ? 'working' : next);
  };

  /** The agents that were told to end and have not yet: a close that does not wait leaves them here, and the host's stop waits for them. */
  const ending = new Set<Promise<void>>();
  /** The agents that are being closed: a resume of the same session waits for its own, so two agents never hold one conversation. */
  const closing = new Map<string, Promise<void>>();

  /** Closes a live session: it is no longer live as soon as this runs, and the agent's end (SIGTERM, then SIGKILL) is waited for unless `wait` is false. */
  async function close({ sessionId }: { sessionId: string }, { wait = true }: { wait?: boolean } = {}) {
    row(sessionId);
    const live = lives.get(sessionId);
    if (live === undefined) return {};
    lives.delete(sessionId);
    revoke(live.invocationId);
    live.cancelIdle?.();
    db.update(sessions).set({ state: 'idle', pid: null, pgid: null, command: null }).where(eq(sessions.id, sessionId)).run();
    notifyWaiters();
    const failed = (error: unknown) => log.error('closing a conversation failed', error);
    let finish!: () => void;
    const finished = new Promise<void>((resolve) => (finish = resolve));
    closing.set(sessionId, finished);
    const done = () => (finish(), closing.get(sessionId) === finished && closing.delete(sessionId));
    if (wait) {
      try {
        await live.conversation.close();
      } catch (error) {
        failed(error);
      } finally {
        done();
      }
    } else {
      const ended = live.conversation.close().catch(failed);
      ending.add(ended);
      void ended.then(() => (ending.delete(ended), done()));
    }
    onLiveChange();
    return {};
  }

  /** The ids of a session's children. */
  const kidsOf = (parentId: string) => db.select({ id: sessions.id }).from(sessions).where(eq(sessions.parentSessionId, parentId)).all().map((kid) => kid.id);

  /** Readies a session and its children to be archived or deleted: refuses, before closing anything, an unknown one, one working or waiting for an approval and a child that does; then closes the idle live ones.
   * An archive does not wait for the agent to end, which can take seconds (the person is watching the row go); a delete does, as its worktree cannot be removed under a running agent. */
  async function settle(sessionId: string, verb: 'archive' | 'delete') {
    notSwitching(sessionId);
    if (row(sessionId).state === 'preparing' || restoring.has(sessionId)) throw new ChatRefused(`This session is being prepared; wait for it to finish, then ${verb} it`);
    const family = [sessionId, ...kidsOf(sessionId)];
    if (family.some((id) => opening.has(id))) throw new ChatRefused(`A child of this session is starting; try again in a moment, then ${verb} it`);
    for (const id of family) {
      const waiting = lives.get(id)?.background.length ?? 0;
      if (waiting > 0) throw new ChatRefused(`${id === sessionId ? 'This session is' : 'A child of this session is'} waiting for ${waiting === 1 ? 'a background task' : 'background tasks'}; stop ${waiting === 1 ? 'it' : 'them'} first, then ${verb} ${id === sessionId ? 'it' : 'the session'}`);
    }
    for (const id of family) {
      const state = lives.get(id)?.state;
      if (state !== undefined && state !== 'idle') throw new ChatRefused(`${id === sessionId ? 'This session' : 'A child of this session'} is ${state === 'working' ? 'working' : 'waiting for an approval'}; interrupt or close it first, then ${verb} ${id === sessionId ? 'it' : 'the session'}`);
    }
    for (const id of family) {
      if (lives.has(id) === false) continue;
      await close({ sessionId: id }, { wait: verb === 'delete' });
      if (lives.has(id)) throw new ChatRefused('This session was resumed meanwhile; close it first'); // a resume that finished during the close
    }
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
  const issueMcp = (sessionId: string, child = false) => {
    const invocationId = randomUUID();
    const url = mcp?.url();
    if (mcp === undefined || url === undefined) return { invocationId, args: undefined };
    return { invocationId, args: { serverName: MCP_SERVER_NAME, url, tools: mcp.tools, token: mcp.registry.issue({ sessionId, invocationId, capabilities: child ? ['read'] : ['read', 'act'] }) } };
  };
  const revoke = (invocationId: string) => mcp?.registry.revokeByInvocation(invocationId);

  async function openConversation({ chosen, runner, command, launch, env }: Launch, args: { folder: string; options: Record<string, string>; resume?: string; child?: boolean; mcp?: { serverName: string; url: string; token: string; tools?: string[] }; instructions?: string }) {
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
      const family = [...kidsOf(sessionId), sessionId]; // the children first: they reference the parent
      db.transaction((tx) => {
        tx.delete(chatEvents).where(inArray(chatEvents.sessionId, family)).run();
        tx.delete(chatTurns).where(inArray(chatTurns.sessionId, family)).run();
        for (const id of family) tx.delete(sessions).where(eq(sessions.id, id)).run();
      });
      for (const id of family) {
        try {
          rmSync(sessionFolder(id), { recursive: true, force: true }); // its attached files
        } catch (error) {
          log.error('the folder of a deleted session could not be removed', error, { sessionId: id });
        }
      }
    } finally {
      deleting.delete(sessionId);
      if (exists(sessionId) === false) told.delete(sessionId);
    }
    return {};
  }

  /** Records a message, starts its turn and hands it to the agent: the person's through `send`, and a child's first one, its task, from the host itself. */
  const deliver = (sessionId: string, live: Live, shown: string, text: string, invoked?: ChatCommand) => {
    live.turn = openTurn();
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
    const live: Live = { conversation, state, streaming: '', approvals: new Map(), tasks: new Set(), background: [], invocationId };
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
   * The `fetch` step of a plan that cuts a worktree from the remote branch of a folder the person already had, ahead of the `worktree` step (ADR 0037): it runs
   * only when `origin/<branch>` is on disk and the last fetch is older than the freshness window. Answers where the worktree starts: `remote`, or `local` when
   * the fetch failed, timed out or took `origin/<branch>` away and the local branch exists. That fetch ends as done and a `notice` says why, so the send goes on.
   */
  async function refresh(sessionId: string, folder: string, branch: string, signal: AbortSignal): Promise<'remote' | 'local'> {
    const remote = `origin/${branch}`;
    const before = await inspectFolder(git, folder).catch(() => undefined); // a folder git cannot read is refused by the worktree step, in words
    if (before === undefined) return 'remote';
    const fresh = before.fetchedAt !== null && clock.now() - before.fetchedAt < FETCH_FRESH_MS;
    if (branch.startsWith('origin/') || before.branches.some((listed) => listed.name === remote) === false || fresh) return 'remote';
    stepEvent(sessionId, 'fetch', 'running');
    let why: string;
    let known = true; // whether `origin/<branch>` is still there to count against
    try {
      const after = await fetchFolder(git, folder, { signal });
      stepEvent(sessionId, 'fetch', 'done');
      if (after.branches.some((listed) => listed.name === remote)) return 'remote';
      why = `${remote} is no longer on origin`;
      known = false;
    } catch (error) {
      if (signal.aborted) return 'remote'; // the person left: the preparation ends at the next check, with no fallback to record
      if (error instanceof ChatRefused === false) log.error('fetching for a new worktree failed', error);
      stepEvent(sessionId, 'fetch', 'done');
      why = error instanceof ChatRefused ? error.message : 'The fetch of origin failed';
    }
    if (before.branches.some((listed) => listed.name === branch && listed.remote === false) === false) {
      if (known) store(sessionId, { kind: 'notice', text: `${why}, so this worktree started from the copy of ${remote} the last fetch left.` });
      return 'remote';
    }
    const counted = known ? await git.run(folder, ['rev-list', '--count', `refs/heads/${branch}..refs/remotes/${remote}`]) : undefined;
    const behind = counted?.ok === true ? Number.parseInt(counted.out, 10) : 0;
    store(sessionId, { kind: 'notice', text: `${why}, so this worktree started from the local branch ${branch}${behind > 0 ? `, which is ${behind} ${behind === 1 ? 'commit' : 'commits'} behind ${remote}` : ''}.` });
    return 'local';
  }

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
    let startFrom = worktree?.startFrom ?? ages().worktreeStart ?? 'remote';
    if (worktree !== undefined && branch !== undefined && startFrom === 'remote' && plan.workspace.kind === 'folder') startFrom = await refresh(sessionId, folder, branch, signal); // its `fetch` step comes before the `worktree` one
    if (signal.aborted) return undefined;
    stepEvent(sessionId, step, 'running');
    try {
      if (worktree !== undefined) {
        if (branch === undefined) throw new ChatRefused('A worktree needs the branch it starts from');
        // an empty name is the host's to generate
        const made = await exclusive(async () => createWorktree(git, folder, { from: await listedAs(folder, plan, branch), startFrom, ...(worktree.name !== undefined && worktree.name !== '' && { name: worktree.name }) }, signal));
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
  async function makeNewProject(sessionId: string, name: string): Promise<boolean> {
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

  /**
   * Once a preparation that cloned or made its workspace has succeeded, the folder is a project in `projects.json` (docs/specs/projects.md, Who writes what): `created` for a
   * new project, `cloned` when the clone step ran in this preparation (a retry counts the one an earlier try did) and `added` for a folder that was only fetched. A folder that
   * is a project already is left as it is. A folder that cannot be written is told in a notice, since the session itself went well.
   */
  async function register(sessionId: string, plan: Plan, folder: string) {
    if (plan.workspace.kind === 'folder') return; // a folder the person chose stays a plain workspace until they add it
    const origin = plan.workspace.kind === newProjectKind ? 'created' : lastStatus(sessionId, 'clone') === 'done' ? 'cloned' : 'added';
    try {
      const listed = readProjectsFile();
      if (listed.ok) await checkWorktreeClash(git, folder, listed.projects);
      const written = updateProjectsFile((current) => (current.some((entry) => samePath(entry.path, folder)) ? current : [...current, { path: folder, origin }]));
      if (written.ok === false) throw new ChatRefused(`projects.json ${written.errors[0]!.path} ${written.errors[0]!.message}`);
    } catch (error) {
      if (error instanceof ChatRefused === false) log.error('registering the project of a session failed', error, { folder });
      store(sessionId, { kind: 'notice', text: `${basename(folder)} was not added to your projects: ${error instanceof ChatRefused ? error.message : 'projects.json could not be written'}.` });
    }
  }

  /**
   * The `action` steps of a preparation at one moment (ADR 0039): the project's actions that are on for `when`, in the listed order, each a step of its own run through
   * `sh -c` in `folder` with the host's environment plus `CARRIER_PROJECT` (the project's base folder) and `CARRIER_FOLDER`. The project is the entry of `projects.json` whose
   * path is `base`, read once for the preparation (`file`); with no action on there is no step. One that finished in an earlier try is skipped, so Try again repeats from the one that stopped.
   * A failure that warns leaves its step done with a notice, one that stops fails the step. False once the preparation must not go on (a stop, or the person left).
   * ponytail: two actions of one moment with the same name count as one in a retry and in the app's list; the app's page can refuse a repeated name when that bites.
   */
  async function runActions(sessionId: string, file: ReturnType<typeof readProjectsFile>, base: string, when: ActionWhen, folder: string, signal: AbortSignal, after = 0): Promise<boolean> {
    if (file.ok === false) {
      // a notice once a preparation: the file's problem, and that an action that would have run did not
      if (told.has(sessionId) === false) store(sessionId, { kind: 'notice', text: `This project's actions did not run: projects.json ${file.errors[0]!.path} ${file.errors[0]!.message}.` });
      told.add(sessionId);
      return true;
    }
    const same = (path: string) => real(expandHome(path)) === real(base);
    const todo = (file.projects.find((entry) => same(entry.path))?.actions ?? []).filter((action) => action.when === when && action.on !== false);
    for (const action of todo) {
      const label = { action: clean(action.name, chatCaps.title), when };
      const finished = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'step'))).orderBy(desc(chatEvents.id)).all().find((event) => event.id > after && event.data.step === 'action' && event.data.action === label.action && event.data.when === when);
      if (finished?.data.status === 'done') continue;
      stepEvent(sessionId, 'action', 'running', undefined, label);
      const result = await shell.run(folder, action.command, { env: { ...env, CARRIER_PROJECT: base, CARRIER_FOLDER: folder }, signal, onProgress: (line) => void progress.set(sessionId, clean(line, chatCaps.preview)) });
      progress.delete(sessionId);
      if (result.ok) {
        stepEvent(sessionId, 'action', 'done', undefined, label);
        continue;
      }
      if (signal.aborted) return false; // the person left: the session goes with its steps
      const end = redact(result.output).trim().slice(-chatCaps.error);
      const why = `${label.action} failed${result.code === null ? '' : ` with exit code ${result.code}`}${end === '' ? '' : `: ${end}`}`;
      if (action.onFail === 'stop') {
        failStep(sessionId, 'action', why, label);
        return false;
      }
      stepEvent(sessionId, 'action', 'done', undefined, label);
      store(sessionId, { kind: 'notice', text: `${why}. The session went on without it.` });
    }
    return true;
  }

  /** The steps of a plan, in the background: it never throws, a failure is recorded as a step that failed. */
  async function prepare(sessionId: string, launch: Launch, base: string, plan: Plan, signal: AbortSignal) {
    try {
      if (plan.workspace.kind === newProjectKind && (await makeNewProject(sessionId, plan.workspace.name)) === false) return;
      if (plan.workspace.kind === 'repo' && (await bring(sessionId, plan.workspace.repo, signal)) === false) return;
      const file = readProjectsFile(); // at each preparation, so a change is for the next one
      if (lastStatus(sessionId, 'clone') === 'done' && (await runActions(sessionId, file, base, 'afterClone', base, signal)) === false) return;
      const folder = await arrange(sessionId, plan.workspace.kind === newProjectKind ? row(sessionId).folder : base, plan, signal);
      if (folder === undefined || signal.aborted) return;
      if ((plan.worktree !== undefined || plan.branch !== undefined) && (await runActions(sessionId, file, base, 'newWorktree', folder, signal)) === false) return;
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
      live.turn = openTurn();
      // a retry sends the same message again, which the conversation already shows
      if (db.select({ id: chatEvents.id }).from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), eq(chatEvents.kind, 'user'))).limit(1).get() === undefined) store(sessionId, { kind: 'user', text: plan.text });
      try {
        conversation.send(plan.text);
        await register(sessionId, plan, base);
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
      told.delete(sessionId);
      onLiveChange();
    }
  }

  /** What a plan needs to run, refusing in words one that cannot. A project's or a repository's folder is the one it will be made or cloned at. */
  const targetOf = (plan: Plan) => {
    const chosen = listed().find((candidate) => candidate.name === plan.agent);
    if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${plan.agent}"`);
    return { launch: launchOf(chosen), folder: plan.workspace.kind === newProjectKind ? projectFolder(plan.workspace.name) : plan.workspace.kind === 'repo' ? projects.repoFolder(plan.workspace.repo) : checkFolder(plan.workspace.folder, carrierHome()) };
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

  /** The options and level a child of `chosen` would have under `parentId` now, undefined when the parent is off the scale. */
  const childPlan = (parentId: string, chosen: ChatAgent, harness: string) => {
    const parent = row(parentId);
    const parentLevel = isScaleHarness(parent.harness) ? levelOf(parent.harness, optionsOf(parentId, parent.options)) : undefined;
    return parentLevel === undefined || !isScaleHarness(harness) ? undefined : childOptions(harness, { ...(chosen.model && { model: chosen.model }), ...chosen.options }, parentLevel);
  };

  /** Why a session may not delegate now, in words (its options as they are now, so a change of mode counts). */
  const delegationRefusalOf = (sessionId: string) => {
    if (!exists(sessionId)) return 'This session no longer exists';
    const found = row(sessionId);
    if (found.parentSessionId !== null) return 'A child session cannot start children of its own';
    return delegationRefusal(found.harness, optionsOf(sessionId, found.options), lives.get(sessionId)?.conversation.appServerVersion);
  };

  /**
   * Starts a child session of `parentId` for a configured agent and sends it the task (ADR 0033). The child is a session of its own agent in the parent's folder,
   * recorded as a plain folder, with the options of that agent lowered to the parent's level. Its row is inserted first, so it holds its slot and its request id
   * while the conversation opens, and goes if the open fails. Everything between the last check and that insert is synchronous, so two calls cannot both take the last slot.
   */
  async function startChild(parentId: string, { agent, task, model, requestId }: { agent: string; task: string; model?: string; requestId?: string }) {
    // a request id seen before is answered with its child, whatever else this call says, and before anything that could refuse it
    const earlier = () => (requestId === undefined ? undefined : db.select({ id: sessions.id }).from(sessions).where(and(eq(sessions.parentSessionId, parentId), eq(sessions.delegationRequestId, requestId))).get());
    // a child still opening is answered once it has opened, or fails the same way the call that opens it does
    const answer = async (childId: string) => {
      await opening.get(childId);
      return { childId };
    };
    const seen = earlier();
    if (seen !== undefined) return answer(seen.id);

    const parent = row(parentId);
    const refused = delegationRefusalOf(parentId);
    if (refused !== undefined) throw new ChatRefused(refused);
    const chosen = listed().find((candidate) => candidate.name === agent);
    if (chosen === undefined) throw new ChatRefused(`There is no chat agent named "${agent}"`);
    if (listAgents().find((candidate) => candidate.name === agent)?.found !== true) throw new ChatRefused(`The agent "${agent}" is not found on this machine`);
    const launch = launchOf(chosen);
    const folder = await folderOf(parent);
    const verdict = (await health({})).agents.find((candidate) => candidate.name === agent)?.state;
    if (verdict === 'signedOut') throw new ChatRefused(`The agent "${agent}" is signed out`);
    if (verdict === 'missing') throw new ChatRefused(`The agent "${agent}" is not found on this machine`);
    if (model !== undefined) await checkModel(agent, model);

    // no await from here to the insert
    const again = earlier();
    if (again !== undefined) return answer(again.id);
    const current = row(parentId);
    if (deleting.has(parentId)) throw new ChatRefused('This session is being deleted');
    // the mode may have changed while the awaits above ran
    const plan = delegationRefusalOf(parentId) === undefined ? childPlan(parentId, chosen, launch.harness) : undefined;
    if (plan === undefined) throw new ChatRefused(delegationRefusalOf(parentId) ?? 'This session\'s options are off the permission scale, so a child cannot be given a level');
    const running = db.select({ n: count() }).from(sessions).where(and(eq(sessions.parentSessionId, parentId), inArray(sessions.state, ['working', 'waiting_approval']))).get()?.n ?? 0;
    if (running >= MAX_RUNNING_CHILDREN) throw new ChatRefused(`This session already has ${MAX_RUNNING_CHILDREN} children working or waiting for an approval; start another when one of them has finished`);
    const options = { ...plan.options, ...(model !== undefined && { model }) };
    const now = clock.now();
    const childId = randomUUID();
    db.insert(sessions).values({ id: childId, agent: chosen.name, harness: launch.harness, folder: current.folder, options, title: titleOf(task), titleSource: 'first_line', state: 'working', createdAt: now, lastActiveAt: now, parentSessionId: parentId, delegationRequestId: requestId ?? null }).run();

    const issued = issueMcp(childId, true);
    const open = (async () => {
      let conversation: ChatConversation | undefined;
      try {
        conversation = await openConversation(launch, { folder, options, child: true, mcp: issued.args });
        for (const [id, value] of Object.entries(options)) checkOption(conversation.options, id, value);
        if (!exists(parentId) || deleting.has(parentId) || row(parentId).archived) throw new ChatRefused('The session that asked for this child no longer exists');
        deliver(childId, attach(childId, conversation, issued.invocationId), task, task);
      } catch (error) {
        if (lives.has(childId)) await close({ sessionId: childId }); // attached, and the task could not be sent
        else {
          revoke(issued.invocationId);
          await conversation?.close().catch((closing) => log.error('closing a refused conversation failed', closing));
        }
        discard(childId);
        throw error;
      } finally {
        opening.delete(childId);
      }
    })();
    opening.set(childId, open); // still before any await: the open above has only run up to its first
    await open;
    return { childId };
  }

  /** How a child of `parentId` stands, from its live state and, once it is not working, from how its one turn (after its last user message) ended; refuses an id that is not that parent's child like one that does not exist. */
  function childReport(parentId: string, childId: string): ChildReport {
    const child = db.select().from(sessions).where(and(eq(sessions.id, childId), eq(sessions.parentSessionId, parentId))).get();
    if (child === undefined) throw new ChatRefused('There is no such session');
    const report = { childId, agent: child.agent };
    const live = lives.get(childId);
    if (live?.state === 'working') return { ...report, state: 'working' };
    if (live?.state === 'waiting_approval') {
      const asked = [...live.approvals.values()];
      const waitingFor = asked.slice(0, CHILD_APPROVALS).map(({ tool, arg, questions }) => ({ tool, ...(arg !== undefined && { arg: cut(arg, CHILD_APPROVAL_ARG) }), ...(questions?.[0] !== undefined && { question: cut(questions[0].question, CHILD_APPROVAL_ARG) }) }));
      return { ...report, state: 'needs_approval', waitingFor, ...(asked.length > CHILD_APPROVALS && { more: asked.length - CHILD_APPROVALS }) };
    }
    const since = db.select({ id: chatEvents.id }).from(chatEvents).where(and(eq(chatEvents.sessionId, childId), eq(chatEvents.kind, 'user'))).orderBy(desc(chatEvents.id)).limit(1).get()?.id ?? 0;
    const turn = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, childId), gt(chatEvents.id, since), inArray(chatEvents.kind, ['assistant', 'error', 'turn_end']))).orderBy(asc(chatEvents.id)).all();
    const end = turn.find((event) => event.kind === 'turn_end');
    const error = turn.findLast((event) => event.kind === 'error');
    // a turn that never ended (closed, or its process died) and said no error was cut off
    if (end?.data.outcome === 'interrupted' || (end === undefined && error === undefined)) return { ...report, state: 'interrupted' };
    if (error?.data.reason === 'usage_limit') return { ...report, state: 'usage_limit' };
    if (error !== undefined || end?.data.outcome === 'error') return { ...report, state: 'error' };
    const text = turn.findLast((event) => event.kind === 'assistant')?.data.text;
    return { ...report, state: 'done', ...(typeof text === 'string' && text !== '' && { message: text.slice(0, CHILD_MESSAGE) }) };
  }

  /** Answers when no child is working or the time is up, whichever comes first. */
  function waitChildren(parentId: string, childIds: string[], timeoutMs: number): Promise<ChildReport[]> {
    const reports = () => childIds.map((childId) => childReport(parentId, childId));
    return new Promise((resolve, reject) => {
      const finish = () => {
        cancel();
        waiters.delete(check);
        try {
          resolve(reports());
        } catch (error) {
          reject(error);
        }
      };
      const check = () => {
        try {
          if (reports().every((report) => report.state !== 'working')) finish();
        } catch (error) {
          cancel();
          waiters.delete(check);
          reject(error);
        }
      };
      const cancel = clock.after(timeoutMs, async () => finish());
      waiters.add(check);
      check();
    });
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
    lives.get(sessionId)?.cancelIdle?.(); // the new agent is being opened: the old one may not close under it, and a refused switch leaves the session as it was
    try {
      const verdict = (await health({})).agents.find((candidate) => candidate.name === agent)?.state;
      if (verdict === 'signedOut') throw new ChatRefused(`The agent "${agent}" is signed out`);
      if (verdict === 'missing') throw new ChatRefused(`The agent "${agent}" is not found on this machine`);
      const folder = await folderOf(current);
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
        if (row(sessionId).archived) throw new ChatRefused('This session was archived meanwhile; restore it first, then switch its agent');
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
    liveCount: () => new Set([...lives.keys(), ...preparing.keys(), ...restoring.keys()]).size,

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
      delegationRefusal: delegationRefusalOf,
      startChild,
      waitChildren,
      related: (sessionId: string, otherId: string) => row(sessionId).parentSessionId === otherId || db.select({ id: sessions.id }).from(sessions).where(and(eq(sessions.id, otherId), eq(sessions.parentSessionId, sessionId))).get() !== undefined,
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

    /** The rows, each with `lastMessage`, `turns` and `model` (see `activity`), `diff` (lines added and removed, null when none or not yet read) and `background` (what the agent waits for after its turn ended: `{ id, kind, description, startedAt }` each; empty when nothing) and `pr` (its pull request: `repo`, `number`, `url`, `state` and `checks`; null while none is known; see `session-data.ts`), `kept` (spared by the clock for unsaved work, only while it is due under the current ages) and `deleteAt` (when the clock deletes it, in ms; null unless archived, with both ages set and not kept). */
    list: ({ archived = false }: { archived?: boolean }) => {
      const { archiveAfterDays, deleteAfterDays } = ages();
      const found = db.select().from(sessions).where(and(eq(sessions.archived, archived), isNull(sessions.parentSessionId))).orderBy(desc(sessions.lastActiveAt)).all();
      if (archived === false) data.kick(found);
      return {
        sessions: found.map((found) => {
          const dueAt = found.archived && archiveAfterDays !== 'never' && deleteAfterDays !== 'never' ? familyClock(found).lastActiveAt + deleteAfterDays * DAY : null;
          const kept = found.keptAt !== null && dueAt !== null && clock.now() >= dueAt; // a session the clock no longer considers (ages raised or never) is not kept
          return { ...summary(found), live: lives.has(found.id), kept, deleteAt: kept ? null : dueAt, ...activity(found.id), ...data.view(found), background: lives.get(found.id)?.background ?? [] };
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
    async openPlan({ plan: asked }: { plan: Plan }) {
      if (asked.text.length > chatCaps.message) throw new ChatRefused(`That message has ${asked.text.length} characters; the most a message can have is ${chatCaps.message}`);
      const target = targetOf(asked);
      const now = clock.now();
      const id = randomUUID();
      const plan = { ...asked, text: claimAttachments(asked.text, id) };
      const created = db
        .insert(sessions)
        .values({ id, agent: target.launch.chosen.name, harness: target.launch.harness, folder: target.folder, plan, title: titleOf(plan.text), titleSource: 'first_line', state: 'preparing', createdAt: now, lastActiveAt: now })
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
      const restoration = restoring.get(sessionId);
      if (restoration !== undefined) {
        restoration.abort.abort(); // a worktree coming back: the session stays, only the action that runs stops
        await restoration.done.catch(() => undefined); // the open that asked for it answers with the refusal
        return { plan: null };
      }
      const { state, plan } = row(sessionId);
      if (state !== 'preparing') throw new ChatRefused('This session is not being prepared, so there is nothing to cancel');
      deleting.add(sessionId); // a retry or a resume that comes in meanwhile is refused
      let released = plan;
      try {
        const running = preparing.get(sessionId);
        running?.abort.abort();
        await running?.done;
        await close({ sessionId }); // the agent that waits to answer the first message
        db.update(sessions).set({ state: 'idle' }).where(eq(sessions.id, sessionId)).run();
        if (plan !== null) released = { ...plan, text: releaseAttachments(plan.text, sessionId) }; // the draft keeps its files
        await deleteSession({ sessionId });
      } finally {
        deleting.delete(sessionId);
      }
      return { plan: released };
    },

    agentOptions: offerOf,

    /** Opens a closed session again from its stored native id, folder and options; a live one is just attached to. */
    async resume({ sessionId }: { sessionId: string }) {
      refuseChild(sessionId, 'resumed');
      notSwitching(sessionId);
      const current = row(sessionId);
      const inFlight = closing.get(sessionId);
      if (inFlight !== undefined) await inFlight; // an agent of this session that is still ending; with none, nothing awaits and the checks below run in the same turn
      if (current.plan !== null) throw new ChatRefused('This session did not finish preparing');
      const present = lives.get(sessionId);
      if (present !== undefined) return { session: summary(current), options: present.conversation.options };
      if (deleting.has(sessionId)) throw new ChatRefused('This session is being deleted');
      const chosen = listed().find((candidate) => candidate.name === current.agent);
      if (chosen === undefined) throw new ChatRefused(`The agent "${current.agent}" of this session is not configured any more`);
      const launch = launchOf(chosen);
      const folder = await folderOf(current);
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
      if (current.workspaceKind === 'worktree' && (clearing.has(sessionId) || existsSync(folder) === false)) {
        // the clock's cleanup took the worktree folder while the provider opened: the agent may not stay in a folder that is going
        revoke(issued.invocationId);
        await conversation.close();
        throw new ChatRefused('This session\'s worktree folder was being cleaned up; open it again to bring it back');
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

    send({ sessionId, text: written, command }: { sessionId: string; text: string; command?: string }) {
      let text = written;
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
      text = claimAttachments(text, sessionId);
      const shown = invoked === undefined ? text : `/${invoked.name}${text === '' ? '' : ` ${text}`}`;
      if (shown.length > chatCaps.message) throw new ChatRefused(`That message has ${shown.length} characters; the most a message can have is ${chatCaps.message}`);
      if (current.title === null) db.update(sessions).set({ title: titleOf(shown), titleSource: 'first_line' }).where(eq(sessions.id, sessionId)).run();
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

    /** Ends the turn that is running, if any, and leaves the session idle for the next message. With no turn running it stops what the agent waits for in the background, or changes nothing. */
    async interrupt({ sessionId }: { sessionId: string }) {
      notSwitching(sessionId);
      row(sessionId);
      const live = lives.get(sessionId);
      if (live?.turn === undefined) {
        // no turn to end, but what the agent waits for in the background can be stopped: that is what the person sees as the session working
        if (live !== undefined) await Promise.all(live.background.map((task) => live.conversation.stopTask?.(task.id).catch((error) => log.error('stopping a background task failed', error))));
        return {};
      }
      try {
        await live.conversation.interrupt();
      } catch (error) {
        log.error('interrupting a conversation failed', error);
      }
      // The adapter says the turn ended; if it did not, the interrupt still did, so the host records it.
      if (live.turn !== undefined) onEvent(sessionId, live, { kind: 'turn_end', outcome: 'interrupted' });
      return {};
    },

    /** Stops one subagent or one background task of the live session; its turn goes on. The row ends when the agent says the task stopped, not here. */
    async stopTask({ sessionId, taskId }: { sessionId: string; taskId: string }) {
      row(sessionId);
      const live = lives.get(sessionId);
      if (live === undefined) throw new ChatRefused('This session is closed');
      if (live.conversation.stopTask === undefined) throw new ChatRefused('This session cannot stop a task');
      if (live.tasks.has(taskId) === false && live.background.some((task) => task.id === taskId) === false) throw new ChatRefused('That task is not running');
      try {
        await live.conversation.stopTask(taskId);
      } catch (error) {
        log.error('stopping a task failed', error);
        throw new ChatRefused('The task could not be stopped');
      }
      return {};
    },

    async setOption({ sessionId, option, value }: { sessionId: string; option: string; value: string }) {
      refuseChild(sessionId, 'given other options');
      notSwitching(sessionId);
      const live = lives.get(sessionId);
      if (live === undefined) throw new ChatRefused('This session is closed');
      checkOption(live.conversation.options, option, value);
      renew(sessionId);
      try {
        await live.conversation.setOption(option, value);
      } catch (error) {
        if (error instanceof ChatRefused) throw error;
        log.error('an option could not be changed', error);
        throw new ChatRefused(`The option "${option}" could not be changed`);
      }
      return { options: live.conversation.options };
    },

    /**
     * `reasoning` is the client asking for the `reasoning` events: one that does not keeps getting the events it knew.
     * `lists` is the `listsRev` the client already has: the options and the commands, which are most of the reply and almost never change, are left
     * out while it is the current one (`listsUnchanged`), and a client that sends none gets them every time.
     */
    events({ sessionId, after = 0, limit, reasoning = false, lists }: { sessionId: string; after?: number; limit: number; reasoning?: boolean; lists?: string }) {
      const current = row(sessionId);
      renew(sessionId);
      const rows = db.select().from(chatEvents).where(and(eq(chatEvents.sessionId, sessionId), gt(chatEvents.id, after), reasoning ? undefined : ne(chatEvents.kind, 'reasoning'))).orderBy(asc(chatEvents.id)).limit(limit).all();
      const live = lives.get(sessionId);
      const options = live?.conversation.options ?? [];
      const commands = live?.conversation.commands ?? [];
      const listsRev = createHash('sha1').update(JSON.stringify([options, commands])).digest('hex').slice(0, 16);
      return {
        // an option event's data has the option's own `id`, which must not take the place of the row's: a client reads `id` as the cursor
        events: rows.map(({ id, at, kind, data }) => (kind === 'option' ? { id, at, kind, option: data.id, value: data.value } : { id, at, kind, ...data })),
        cursor: rows.at(-1)?.id ?? after,
        // what a row of `list` says of whether the session runs, so a client that reads `events` asks for no list
        session: { ...summary(current), live: live !== undefined, background: live?.background ?? [] },
        streaming: live?.streaming ?? '',
        progress: progress.get(sessionId) ?? null,
        approvals: [...(live?.approvals.values() ?? [])],
        listsRev,
        // the keys are named in both replies so they have one type; JSON drops the undefined ones
        ...(lists === listsRev ? { listsUnchanged: true as const, options: undefined, commands: undefined } : { listsUnchanged: undefined, options, commands }),
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
      db.update(sessions).set({ title: named, titleSource: 'renamed' }).where(eq(sessions.id, sessionId)).run();
      return {};
    },

    /** Writes the session's title again from its first message and first reply with the chosen text generator, over any title (the person asked); answers it. Refused in words, with the title as it was, when the generator gives none. */
    async regenerateTitle({ sessionId }: { sessionId: string }) {
      refuseChild(sessionId, 'retitled');
      const first = firstMessage(sessionId);
      if (first === undefined || first.text.trim() === '') throw new ChatRefused('This session has no message to write a title from yet');
      let title: string;
      try {
        title = await generateTitle(sessionId, first.text, firstReply(sessionId, first.id));
      } catch (error) {
        throw new ChatRefused(`Could not write a title: ${error instanceof TextGeneratorFailed ? error.message : 'the text generator failed'}`);
      }
      db.update(sessions).set({ title, titleSource: 'generated' }).where(eq(sessions.id, sessionId)).run();
      return { title };
    },

    /** Starts writing a title with the chosen text generator for every session of the list and the archive whose title is still its first line, one at a time in the background, and answers how many it started. */
    regenerateTitles() {
      try {
        textGenerator.chosen?.();
      } catch (error) {
        throw new ChatRefused(`Could not write titles: ${error instanceof TextGeneratorFailed ? error.message : 'no text generator is chosen; choose one in Providers'}`);
      }
      const candidates: { id: string; first: { id: number; text: string } }[] = [];
      for (const found of db.select().from(sessions).where(isNull(sessions.parentSessionId)).orderBy(desc(sessions.lastActiveAt)).all()) {
        if (deleting.has(found.id) || titleSourceOf(found) !== 'first_line') continue;
        const first = firstMessage(found.id);
        if (first !== undefined && first.text.trim() !== '') candidates.push({ id: found.id, first });
      }
      if (candidates.length > 0) {
        void (async () => {
          for (const { id, first } of candidates) {
            if (closed) return;
            const current = db.select().from(sessions).where(eq(sessions.id, id)).get();
            if (current === undefined || deleting.has(id) || titleSourceOf(current) !== 'first_line') continue;
            try {
              const title = await generateTitle(id, first.text, firstReply(id, first.id));
              if (closed) return;
              const latest = db.select().from(sessions).where(eq(sessions.id, id)).get();
              if (latest === undefined || deleting.has(id) || titleSourceOf(latest) !== 'first_line') continue;
              db.update(sessions).set({ title, titleSource: 'generated' }).where(eq(sessions.id, id)).run();
            } catch {
              if (closed) return;
              // already logged in generateTitle; skip and go on with the rest
            }
          }
        })();
      }
      return { started: candidates.length };
    },

    /** Where the session's title came from, for the automatic title and the bulk one: `first_line`, `generated` or `renamed`, null when it has no title. */
    titleSource: (sessionId: string) => titleSourceOf(row(sessionId)),

    /**
     * The clock's pass: archives each session left alone for `archiveAfterDays`, then deletes each archived one left alone for `deleteAfterDays`, sparing
     * (marking `keptAt`) one whose worktree holds unsaved work. A working, waiting or live one is looked at again on the next pass.
     */
    async applyClock({ archiveAfterDays, deleteAfterDays, worktreeCleanup }: LiveSettings) {
      const now = clock.now();
      for (const found of db.select().from(sessions).where(and(eq(sessions.archived, false), isNull(sessions.parentSessionId))).all()) {
        if (switching.has(found.id)) continue; // a switch is opening its new conversation; the next pass looks again
        const { lastActiveAt, live } = familyClock(found);
        if (idleFor({ state: found.state, lastActiveAt }, live, now, archiveAfterDays)) db.update(sessions).set({ archived: true }).where(eq(sessions.id, found.id)).run();
      }
      if (worktreeCleanup !== undefined) await cleanWorktrees(worktreeCleanup, now);
      if (archiveAfterDays === 'never') return;
      for (const { id } of db.select().from(sessions).where(and(eq(sessions.archived, true), isNull(sessions.parentSessionId))).all()) {
        if (closed) return;
        try {
          // read again after each wait: the person may have restored or resumed it meanwhile, or the host may be shutting down
          const due = () => {
            if (closed) return undefined;
            const found = db.select().from(sessions).where(eq(sessions.id, id)).get();
            if (found?.archived !== true) return undefined;
            const { lastActiveAt, live } = familyClock(found);
            return idleFor({ state: found.state, lastActiveAt }, live, now, deleteAfterDays) ? found : undefined;
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

    /**
     * A project's worktrees for its page: the main clone and each worktree git lists for the project's folder that lies under the worktrees folder and is still on disk,
     * joined to the session whose worktree it is (none for an orphan). Its age is the session's last activity, or the folder's modification time with no session.
     * The state, in this order: the session is open, it has uncommitted changes, its session's pull request is merged (so a squash merge is not "not pushed"),
     * it has commits no other branch holds, else clean. The main clone says only whether it has uncommitted changes, commits on its branch that no remote holds, or neither,
     * which is what the app reads before it moves a project to the Trash.
     */
    async projectWorktrees({ folder }: { folder: string }): Promise<ProjectWorktrees> {
      const { main, entries } = await readProjectWorktrees(folder);
      const unsaved = await previewMain(git, main.path, main.branch);
      return { main: { ...main, state: unsaved.dirty > 0 ? 'uncommitted' : unsaved.unpushed > 0 ? 'notPushed' : 'clean' }, worktrees: entries.map(({ worktree }) => worktree) };
    },

    /** Removes only the folder of one worktree of a project and keeps its branch and its session, which brings the folder back on its next message; refused in words while its session is open or it has uncommitted changes. */
    async removeProjectWorktree({ folder, path }: { folder: string; path: string }) {
      const { base, entries } = await readProjectWorktrees(folder);
      const entry = entries.find((candidate) => candidate.worktree.path === path);
      if (entry === undefined) throw new ChatRefused('That is not a worktree of this project');
      await removeProjectEntry(base, entry);
      return {};
    },

    /**
     * The worktrees of a project whose session's pull request is merged: the ones Clean up would remove, each with the bytes its folder holds, and the ones nothing lets it remove with the reason.
     * With `run` it removes them (each one checked again just before) and answers what it removed and what it skipped.
     */
    async cleanProjectWorktrees({ folder, run }: { folder: string; run: boolean }) {
      const { base, entries } = await readProjectWorktrees(folder);
      const removed: { path: string; bytes: number }[] = [];
      const skipped: { path: string; reason: string }[] = [];
      for (const entry of entries.filter(({ found }) => found?.prState === 'merged')) {
        const { path } = entry.worktree;
        const reason = blockOf(entry);
        if (reason !== null) {
          skipped.push({ path, reason });
          continue;
        }
        const bytes = await folderBytes(path);
        if (run) {
          try {
            await removeProjectEntry(base, entry);
          } catch (error) {
            if (error instanceof ChatRefused === false) throw error;
            skipped.push({ path, reason: error.message });
            continue;
          }
        }
        removed.push({ path, bytes });
      }
      return { removed, skipped };
    },

    /** What a folder is as a git repository, for the person to choose how to work in it. */
    workspace: async ({ folder }: { folder: string }) => inspectFolder(git, checkFolder(folder, carrierHome())),

    /** Fetches `origin` of a folder and answers what it is after it. */
    fetch: async ({ folder, ifStale }: { folder: string; ifStale?: boolean }) => fetchFolder(git, checkFolder(folder, carrierHome()), ifStale === true ? { now: clock.now() } : {}),

    /** A free name for a worktree of a folder, from the StarCraft word lists. */
    suggestName: async ({ folder }: { folder: string }) => suggestName(git, checkFolder(folder, carrierHome())),

    /** Whether a typed worktree name is valid and free. */
    checkName: async ({ folder, name }: { folder: string; name: string }) => checkName(git, checkFolder(folder, carrierHome()), name),

    /** Closes every live session: the host's stop. */
    async closeAll() {
      closed = true;
      // At once: each agent's group has its own grace before the SIGKILL, and a host that ends in a hurry (a crash) must signal them all first.
      await Promise.all([...lives.keys()].map((sessionId) => close({ sessionId })));
      await Promise.all(ending);
    },
  };
}

export type ChatSessions = ReturnType<typeof createSessions>;
