import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { eq } from 'drizzle-orm';
import { openChatDatabase } from './db.ts';
import { sessions } from './schema.ts';
import { sweepDeadHost, type Processes } from './sweep.ts';

let dir: string;
beforeEach(() => void (dir = mkdtempSync(join(tmpdir(), 'sw-'))));
afterEach(() => rmSync(dir, { recursive: true, force: true }));

/** A process table of a few made-up processes; a group dies on SIGTERM unless it is listed in `ignoresTerm`. */
function table(commands: Record<number, string>, ignoresTerm: number[] = []) {
  const groups = new Set(Object.keys(commands).map(Number));
  const signals: string[] = [];
  const processes: Processes = {
    commandOf: (pid) => commands[pid],
    groupAlive: (pgid) => groups.has(pgid),
    signalGroup(pgid, signal) {
      signals.push(`${signal} ${pgid}`);
      if (signal === 'SIGKILL' || !ignoresTerm.includes(pgid)) groups.delete(pgid);
    },
    sleep: async () => {},
  };
  return { processes, signals };
}

function recorded(...rows: { id: string; pid: number; command: string; nativeId?: string }[]) {
  const db = openChatDatabase(join(dir, 'chat.db'));
  for (const { id, pid, command, nativeId } of rows) {
    db.insert(sessions).values({ id, agent: 'claude', harness: 'claude', folder: '/work', state: 'working', pid, pgid: pid, command, nativeId: nativeId ?? null, createdAt: 1, lastActiveAt: 1 }).run();
  }
  return db;
}
const rowOf = (db: ReturnType<typeof openChatDatabase>, id: string) => db.select().from(sessions).where(eq(sessions.id, id)).get()!;

test('a group alive with the recorded command is ended, one with another command is left alone, one gone only loses its record', async () => {
  const db = recorded(
    { id: 'ours', pid: 100, command: '/bin/claude', nativeId: 'n1' },
    { id: 'reused', pid: 200, command: '/bin/claude' },
    { id: 'gone', pid: 300, command: '/bin/claude' },
  );
  const { processes, signals } = table({ 100: '/bin/claude --print', 200: '/usr/bin/vim notes.txt' });

  expect(await sweepDeadHost(db, processes)).toBe(1);

  expect(signals).toEqual(['SIGTERM 100']);
  for (const id of ['ours', 'reused', 'gone']) expect(rowOf(db, id)).toMatchObject({ state: 'idle', pid: null, pgid: null, command: null });
  expect(rowOf(db, 'ours').nativeId).toBe('n1'); // still resumable
  expect(processes.groupAlive(200)).toBe(true);
});

test('a group that ignores SIGTERM gets SIGKILL after the grace', async () => {
  const db = recorded({ id: 'stubborn', pid: 100, command: '/bin/claude' });
  const { processes, signals } = table({ 100: '/bin/claude' }, [100]);
  await sweepDeadHost(db, processes, 300);
  expect(signals).toEqual(['SIGTERM 100', 'SIGKILL 100']);
});

test('a group that cannot be signalled keeps its record for the next start', async () => {
  const db = recorded({ id: 'denied', pid: 100, command: '/bin/claude' });
  const { processes } = table({ 100: '/bin/claude' });
  processes.signalGroup = () => {
    throw new Error('EPERM');
  };
  expect(await sweepDeadHost(db, processes)).toBe(0);
  expect(rowOf(db, 'denied')).toMatchObject({ pid: 100, pgid: 100 });
});
