import { existsSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { openDatabase, type Db } from '../storage/db.ts';
import { executionEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epics, epicStates } from '../storage/schema.ts';
import { FakeClock } from './fake.ts';
import { purgeExpired, retentionMs, sessionDirsFrom, startRetention, type SessionDirs } from './retention.ts';

const DAY = 24 * 60 * 60 * 1000;
let dir: string;
let db: Db;
let dirs: SessionDirs;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-retention-'));
  db = openDatabase(join(dir, 'carrier.db'));
  dirs = { claude: join(dir, 'claude'), codex: join(dir, 'codex') };
});
afterEach(() => {
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const logsDir = () => join(dir, 'engine', 'logs');
const logs = (id: string) => join(logsDir(), 'executions', id);
// Where the CLIs really keep a session (docs/research/headless-agents.md), whichever harness ran it.
const claudeSession = (id: string) => join(dirs.claude, 'projects', '-Users-me-solve-worktrees-demo-feature', `${id}.jsonl`);
const codexSession = (id: string) => join(dirs.codex, 'sessions', '2026', '10', '15', `rollout-2026-10-15T20-35-49-${id}.jsonl`);
const session = (id: string) => [claudeSession(id), codexSession(id)];

/** One epic with one execution whose log folder and sessions (both CLIs' layouts) exist on disk. */
function seed(name: string, status: (typeof epicStates)[number], finishedAt: number | null) {
  const epic = db.insert(epics).values({ repo: 'AshuLab/a', issue: db.select().from(epics).all().length + 1, status, finishedAt }).returning().get();
  db.insert(executions).values({ executionId: `x-${name}`, epicId: epic.id, stage: 'ship', sessionId: `s-${name}`, resultPath: 'r', startedAt: 0 }).run();
  mkdirSync(logs(`x-${name}`), { recursive: true });
  writeFileSync(join(logs(`x-${name}`), 'stdout.log'), 'out');
  for (const file of session(`s-${name}`)) {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, '{}');
  }
  mkdirSync(join(dirname(claudeSession(`s-${name}`)), `s-${name}`), { recursive: true }); // what a Claude session spawned
}
const sessionFolder = (name: string) => join(dirname(claudeSession(`s-${name}`)), `s-${name}`);
const gone = (name: string) => !existsSync(logs(`x-${name}`)) && session(`s-${name}`).every((f) => !existsSync(f)) && !existsSync(sessionFolder(name));
const kept = (name: string) => existsSync(logs(`x-${name}`)) && session(`s-${name}`).every((f) => existsSync(f)) && existsSync(sessionFolder(name));

test('deletes logs and sessions of finished epics at 30 days, not before, whatever the finished status', () => {
  const now = 100 * DAY;
  seed('ready', 'ready_for_test', now - retentionMs);
  seed('merged', 'merged', now - 90 * DAY);
  seed('cancelled', 'cancelled', now - 31 * DAY);
  seed('recent', 'merged', now - retentionMs + 1);
  purgeExpired(db, logsDir(), now, dirs);
  expect([gone('ready'), gone('merged'), gone('cancelled'), kept('recent')]).toEqual([true, true, true, true]);
});

test('keeps everything of queued, running, needs_human and repo_removed epics, however old', () => {
  const now = 1000 * DAY;
  for (const status of ['queued', 'running', 'needs_human', 'repo_removed'] as const) seed(status, status, 0);
  seed('nofinish', 'cancelled', null);
  purgeExpired(db, logsDir(), now, dirs);
  for (const name of ['queued', 'running', 'needs_human', 'repo_removed', 'nofinish']) expect(kept(name)).toBe(true);
});

test('deletes the stored events with the logs they were read from, and only those', () => {
  const now = 100 * DAY;
  seed('old', 'merged', 0);
  seed('recent', 'merged', now);
  for (const name of ['old', 'recent']) db.insert(executionEvents).values({ executionId: `x-${name}`, at: 1, kind: 'say' }).run();
  purgeExpired(db, logsDir(), now, dirs);
  expect(db.select().from(executionEvents).all().map((e) => e.executionId)).toEqual(['x-recent']);
});

test('keeps the interrupted executions of a running epic', () => {
  seed('int', 'running', 0);
  db.update(executions).set({ status: 'interrupted', finishedAt: 1 }).run();
  purgeExpired(db, logsDir(), 1000 * DAY, dirs);
  expect(kept('int')).toBe(true);
});

test('leaves SQLite rows and workspace folders intact', () => {
  const workspace = join(dir, 'worktrees', 'ws');
  mkdirSync(workspace, { recursive: true });
  writeFileSync(join(workspace, 'file.txt'), 'work');
  seed('old', 'merged', 0);
  const before = { epics: db.select().from(epics).all(), executions: db.select().from(executions).all() };
  purgeExpired(db, logsDir(), 100 * DAY, dirs);
  expect(gone('old')).toBe(true);
  expect({ epics: db.select().from(epics).all(), executions: db.select().from(executions).all() }).toEqual(before);
  expect(existsSync(join(workspace, 'file.txt'))).toBe(true);
});

test('a symlinked session is removed without following it, and an id with path pieces is ignored', () => {
  const outside = join(dir, 'outside');
  mkdirSync(outside);
  writeFileSync(join(outside, 'precious'), 'x');
  seed('link', 'merged', 0);
  rmSync(sessionFolder('link'), { recursive: true });
  symlinkSync(outside, sessionFolder('link'));
  seed('evil', 'merged', 0);
  db.update(executions).set({ sessionId: '../../outside' }).where(eq(executions.executionId, 'x-evil')).run();
  purgeExpired(db, logsDir(), 100 * DAY, dirs);
  expect(existsSync(sessionFolder('link'))).toBe(false);
  expect(existsSync(join(outside, 'precious'))).toBe(true);
});

test('a logs folder symlinked out of orchestrator/ is not deleted from', () => {
  const outside = join(dir, 'outside');
  mkdirSync(join(outside, 'x-x'), { recursive: true });
  seed('x', 'merged', 0);
  rmSync(join(logsDir(), 'executions'), { recursive: true });
  symlinkSync(outside, join(logsDir(), 'executions'));
  purgeExpired(db, logsDir(), 100 * DAY, dirs);
  expect(existsSync(join(outside, 'x-x'))).toBe(true);
  expect(session('s-x').some((f) => existsSync(f))).toBe(false);
});

test('only the sessions of expired epics go: the id decides, other sessions and the CLIs\' other folders stay', () => {
  seed('old', 'merged', 0);
  seed('live', 'running', 0);
  const other = claudeSession('11111111-2222-3333-4444-555555555555');
  const config = join(dirs.claude, 'settings.json');
  mkdirSync(dirname(other), { recursive: true });
  writeFileSync(other, '{}');
  writeFileSync(config, '{}');
  const deleted = purgeExpired(db, logsDir(), 100 * DAY, dirs);
  expect(deleted).toEqual(expect.arrayContaining([claudeSession('s-old'), sessionFolder('old'), codexSession('s-old')]));
  expect([other, config].every(existsSync)).toBe(true);
  expect(kept('live')).toBe(true);
});

test('a folder named like a session id is only removed beside its transcript, and symlinked project folders are not walked', () => {
  seed('old', 'merged', 0);
  const lone = join(dirname(claudeSession('s-old')), 's-old-lone');
  mkdirSync(lone);
  const outside = join(dir, 'outside');
  mkdirSync(outside);
  writeFileSync(join(outside, 's-old.jsonl'), 'precious');
  symlinkSync(outside, join(dirs.claude, 'projects', '-linked'));
  db.update(executions).set({ sessionId: 's-old-lone' }).run();
  purgeExpired(db, logsDir(), 100 * DAY, dirs);
  expect(existsSync(lone)).toBe(true); // no s-old-lone.jsonl next to it
  db.update(executions).set({ sessionId: 's-old' }).run();
  purgeExpired(db, logsDir(), 100 * DAY, dirs);
  expect(existsSync(join(outside, 's-old.jsonl'))).toBe(true);
  expect(existsSync(claudeSession('s-old'))).toBe(false);
});

// A session written under a folder other than the environment's: one file per layout, in that folder.
function seedIn(configDir: string, name: string, harness: 'claude' | 'codex', status: (typeof epicStates)[number], finishedAt: number | null) {
  const epic = db.insert(epics).values({ repo: 'AshuLab/a', issue: db.select().from(epics).all().length + 1, status, finishedAt }).returning().get();
  db.insert(executions).values({ executionId: `x-${name}`, epicId: epic.id, stage: 'ship', harness, configDir, sessionId: `s-${name}`, resultPath: 'r', startedAt: 0 }).run();
  mkdirSync(logs(`x-${name}`), { recursive: true });
  const file = harness === 'claude'
    ? join(configDir, 'projects', '-Users-me-demo', `s-${name}.jsonl`)
    : join(configDir, 'sessions', '2026', '10', '15', `rollout-2026-10-15T20-35-49-s-${name}.jsonl`);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, '{}');
  return file;
}

test('an epic with executions in two config folders loses its sessions from both, and its logs', () => {
  const a = join(dir, 'login-a');
  const b = join(dir, 'login-b');
  const fileA = seedIn(a, 'a', 'claude', 'merged', 0);
  const fileB = seedIn(b, 'b', 'codex', 'merged', 0);
  db.update(executions).set({ epicId: db.select().from(executions).where(eq(executions.executionId, 'x-a')).get()!.epicId }).where(eq(executions.executionId, 'x-b')).run(); // one epic, two logins
  const deleted = purgeExpired(db, logsDir(), 100 * DAY, dirs);
  expect(deleted).toEqual(expect.arrayContaining([fileA, fileB, logs('x-a'), logs('x-b')]));
  expect([fileA, fileB, logs('x-a'), logs('x-b')].some(existsSync)).toBe(false);
});

test('the sessions of an unfinished epic in another config folder are not touched', () => {
  const files = (['queued', 'running', 'needs_human', 'repo_removed'] as const).map((status) => seedIn(join(dir, 'login'), status, 'claude', status, 0));
  purgeExpired(db, logsDir(), 1000 * DAY, dirs);
  expect(files.every(existsSync)).toBe(true);
});

test('a recorded config folder that is not absolute is ignored: nothing is deleted under it', () => {
  seed('old', 'merged', 0);
  const relative = join(dir, 'rel');
  const file = join(relative, 'projects', '-p', 's-old.jsonl');
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, '{}');
  db.update(executions).set({ configDir: 'rel' }).run();
  const previous = process.cwd();
  process.chdir(dir);
  try {
    purgeExpired(db, logsDir(), 100 * DAY, dirs);
  } finally {
    process.chdir(previous);
  }
  expect(existsSync(file)).toBe(true);
  expect(existsSync(claudeSession('s-old'))).toBe(true); // not redirected to the environment's folder either
});

test('CLAUDE_CONFIG_DIR and CODEX_HOME decide where the CLIs are looked up, with the CLIs\' own defaults', () => {
  expect(sessionDirsFrom({ CLAUDE_CONFIG_DIR: '/c', CODEX_HOME: '/x' })).toEqual({ claude: '/c', codex: '/x' });
  expect(sessionDirsFrom({})).toEqual({ claude: join(homedir(), '.claude'), codex: join(homedir(), '.codex') });
});

test('runs at startup and again every 24 hours on the injected clock, until stopped', async () => {
  const clock = new FakeClock();
  seed('a', 'merged', -retentionMs); // already expired at t=0
  seed('b', 'merged', 0); // expires at t=30d
  const stop = startRetention(db, logsDir(), clock, dirs);
  expect([gone('a'), kept('b')]).toEqual([true, true]);
  await clock.advance(29 * DAY);
  expect(kept('b')).toBe(true);
  await clock.advance(DAY);
  expect(gone('b')).toBe(true);
  seed('c', 'merged', 0);
  stop();
  await clock.advance(5 * DAY);
  expect(kept('c')).toBe(true);
});
