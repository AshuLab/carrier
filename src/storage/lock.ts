import { chmodSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import Database from 'better-sqlite3';

export type Lock = { ok: true; release: () => void } | { ok: false };

// The lock is an exclusive SQLite transaction on a file in `orchestrator/`, held for the life of
// the process. The OS drops it when the process dies, so a crash never leaves it stuck.
export function acquireLock(orchestratorDir: string): Lock {
  mkdirSync(orchestratorDir, { recursive: true });
  chmodSync(orchestratorDir, 0o700); // the control socket, logs and results in here are for the user only, also in a folder an older version made
  // timeout 0: no waiting, a held lock fails immediately with SQLITE_BUSY.
  const db = new Database(join(orchestratorDir, 'carrier.lock'), { timeout: 0 });
  try {
    db.exec('BEGIN EXCLUSIVE');
  } catch (error) {
    db.close();
    if (error instanceof Error && 'code' in error && error.code === 'SQLITE_BUSY') return { ok: false };
    throw error;
  }
  return { ok: true, release: () => db.close() };
}
