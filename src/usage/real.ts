import { execFile, spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { realClock } from '../orchestration/clock.ts';
import { listLocalModels } from '../harnesses/local.ts';
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
