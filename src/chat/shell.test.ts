import { mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { realShell, STOP_GRACE_MS } from './shell.ts';

// Harmless commands in a temp folder: what the port promises, with the machine's own sh.
let dir: string;
beforeEach(() => void (dir = realpathSync(mkdtempSync(join(tmpdir(), 'sh-')))));
afterEach(() => rmSync(dir, { recursive: true, force: true }));
const run = (command: string, signal = new AbortController().signal) => {
  const lines: string[] = [];
  return realShell.run(dir, command, { env: { ...process.env, CARRIER_FOLDER: dir }, signal, onProgress: (line) => lines.push(line) }).then((result) => ({ result, lines }));
};

test('a command runs through sh in the folder with the environment it is given, and its lines are the progress', async () => {
  const { result, lines } = await run('pwd; echo "$CARRIER_FOLDER"; echo "\\033[32mgreen\\033[0m" >&2');
  expect(result).toEqual({ ok: true });
  expect(lines).toEqual([dir, dir, 'green']);
});

test('a command that fails says its exit code and the end of its output, and one that cannot start says so', async () => {
  expect((await run('echo one; echo two >&2; exit 3')).result).toMatchObject({ ok: false, code: 3, output: expect.stringMatching(/one\ntwo|two\none/) });
  expect(await realShell.run(join(dir, 'gone'), 'echo hi', { env: process.env, signal: new AbortController().signal, onProgress: () => {} })).toMatchObject({ ok: false, code: null });
});

test('an abort stops the command and what it started, and a signal already aborted runs nothing', async () => {
  const abort = new AbortController();
  const running = run('sleep 30 & wait', abort.signal);
  setTimeout(() => abort.abort(), 100);
  expect((await running).result).toMatchObject({ ok: false, aborted: true });
  expect((await run('echo never', AbortSignal.abort())).result).toMatchObject({ ok: false, aborted: true, output: '' });
});

test('a command that ignores the stop is killed once the grace passes, and what it started with it', async () => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  try {
    const abort = new AbortController();
    let ready!: () => void;
    const traps = new Promise<void>((resolve) => (ready = resolve));
    const running = realShell.run(dir, "trap '' TERM; echo ready; sleep 30 & wait", { env: process.env, signal: abort.signal, onProgress: (line) => line === 'ready' && ready() });
    await traps;
    abort.abort();
    let ended = false;
    void running.then(() => (ended = true));
    await vi.advanceTimersByTimeAsync(STOP_GRACE_MS - 1);
    await new Promise((resolve) => setImmediate(resolve));
    expect(ended).toBe(false); // it still holds the stop off: SIGTERM alone does not end it
    await vi.advanceTimersByTimeAsync(1);
    expect(await running).toMatchObject({ ok: false, aborted: true });
  } finally {
    vi.useRealTimers();
  }
});
