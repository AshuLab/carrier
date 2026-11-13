import { execFile, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { open, readdir, readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { realClock } from '../orchestration/clock.ts';
import { listLocalModels } from '../harnesses/local.ts';
import type { HistoryPorts } from './history.ts';
import type { UsagePorts } from './types.ts';

/** The ports on the real machine. The unit tests never use them; the gated integration test does. */
export const realUsagePorts: UsagePorts = {
  clock: realClock,
  async http({ url, method = 'GET', headers, body, timeoutMs }) {
    const response = await fetch(url, { method, headers, body, signal: AbortSignal.timeout(timeoutMs) });
    return { status: response.status, json: await response.json().catch(() => undefined) };
  },
  run: (command, args, { env, timeoutMs }) =>
    new Promise((resolve, reject) => {
      const child = execFile(command, args, { env, timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 }, (error, stdout) => {
        if (error === null) return resolve({ code: 0, stdout });
        const { code, killed } = error as NodeJS.ErrnoException & { killed?: boolean };
        if (typeof code === 'number') return resolve({ code, stdout });
        reject(Object.assign(new Error('the command did not run'), { code: killed ? 'ETIMEDOUT' : code }));
      });
      child.stdin?.end();
    }),
  spawnRpc(command, args, env) {
    const child = spawn(command, args, { env, stdio: ['pipe', 'pipe', 'ignore'], detached: true });
    return {
      send: (line) => void child.stdin.write(`${line}\n`),
      onLine(fn) {
        let pending = '';
        child.stdout.on('data', (chunk: Buffer) => {
          const lines = (pending + chunk.toString()).split('\n');
          pending = lines.pop() ?? '';
          lines.forEach(fn);
        });
      },
      onExit(fn) {
        child.on('error', fn);
        child.on('close', () => fn());
      },
      kill() {
        child.stdin.on('error', () => {});
        try {
          process.kill(-child.pid!, 'SIGTERM'); // the child leads its own group, so whatever it started ends with it
        } catch {
          // already gone
        }
      },
    };
  },
  files: { read: (path) => readFile(path, 'utf8') },
  localModels: (kind) => listLocalModels(kind),
};

/** The history's ports on the real machine. The unit tests use them over temporary folders. */
export const realHistoryPorts: Omit<HistoryPorts, 'clock'> = {
  files: {
    async list(root, suffix) {
      try {
        return (await readdir(root, { recursive: true })).filter((name) => name.endsWith(suffix)).map((name) => join(root, name));
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') return [];
        throw error;
      }
    },
    stat: async (path) => {
      const { size, mtimeMs } = await stat(path);
      return { size, mtimeMs };
    },
    async read(path, from) {
      const file = await open(path, 'r');
      try {
        const { size } = await file.stat();
        const buffer = Buffer.alloc(Math.max(0, size - from));
        const { bytesRead } = await file.read(buffer, 0, buffer.length, from);
        return buffer.subarray(0, bytesRead);
      } finally {
        await file.close();
      }
    },
  },
  openReadonly(file) {
    if (existsSync(file) === false) return undefined;
    const db = new Database(file, { readonly: true, fileMustExist: true });
    db.pragma('busy_timeout = 100');
    return {
      hasTable: (name) => db.prepare("select 1 from sqlite_master where type = 'table' and name = ?").get(name) !== undefined,
      rows: (sql) => db.prepare(sql).iterate() as Iterable<Record<string, unknown>>,
      close: () => void db.close(),
    };
  },
};
