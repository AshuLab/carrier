import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { afterAll, beforeAll, expect, test } from 'vitest';
import { executionOutput, rotatingFile, taskContext } from './logger.ts';

test('rotatingFile moves a full file aside and keeps at most `keep` files', () => {
  const folder = mkdtempSync(join(tmpdir(), 'carrier-rotate-'));
  const log = join(folder, 'logs', 'chat-host.log');
  try {
    const write = rotatingFile(log, 10, 3);
    for (const line of ['aaaa\n', 'bbbb\n', 'cccc\n', 'dddd\n', 'eeee\n', 'ffff\n', 'gggg\n']) write(line);
    expect(readFileSync(log, 'utf8')).toBe('gggg\n');
    expect(readFileSync(`${log}.1`, 'utf8')).toBe('eeee\nffff\n');
    expect(readFileSync(`${log}.2`, 'utf8')).toBe('cccc\ndddd\n');
    expect(existsSync(`${log}.3`)).toBe(false);
    // a restart appends to what is there and counts it
    rotatingFile(log, 10, 3)('hhhh\n');
    expect(readFileSync(log, 'utf8')).toBe('gggg\nhhhh\n');
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});

test('rotatingFile never throws when the log was deleted under it: a new one starts and says so', () => {
  const folder = mkdtempSync(join(tmpdir(), 'carrier-rotate-'));
  const log = join(folder, 'logs', 'chat-host.log');
  try {
    const write = rotatingFile(log, 10, 3);
    write('aaaa\nbbbb\n');
    rmSync(join(folder, 'logs'), { recursive: true });
    write('cccc\n');
    expect(readFileSync(log, 'utf8')).toMatch(/could not be rotated.*\ncccc\n$/s);
    write('dddd\n');
    expect(readFileSync(log, 'utf8')).toBe('dddd\n');
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});

test('universal-logger exposes createScopedLogger', () => {
  expect(typeof createScopedLogger).toBe('function');
});

test('taskContext derives the role from the stage and adds the round only when there is one', () => {
  const base = { repo: 'a/b', epic: 3, executionId: 'x' };
  expect(taskContext({ ...base, stage: 'review', round: 2 })).toEqual({ ...base, role: 'reviewer', stage: 'review', round: 2 });
  expect(taskContext({ ...base, stage: 'ship', round: null })).toEqual({ ...base, role: 'author', stage: 'ship' });
});

test('taskContext names the slot of a review when it has one', () => {
  const base = { repo: 'a/b', epic: 3, executionId: 'x', stage: 'review' as const };
  expect(taskContext({ ...base, reviewer: 'reviewer-2' }).role).toBe('reviewer-2');
  expect(taskContext({ ...base, reviewer: 'lead' }).role).toBe('lead');
  expect(taskContext({ ...base, stage: 'ship', reviewer: null }).role).toBe('author');
});

// One real process that logs and then gets Ctrl+C: it has no handler, so only writeSync keeps what it emitted.
const dir = mkdtempSync(join(tmpdir(), 'carrier-log-'));
const file = join(dir, 'logs', 'orchestrator.log');
let stdout = '';
let stderr = '';
let lines: string[];
beforeAll(async () => {
  const child = spawn(process.execPath, [join(import.meta.dirname, 'logger.fixture.ts'), file]);
  child.stderr.on('data', (d) => (stderr += d));
  const closed = once(child, 'close');
  const [first] = await once(child.stdout, 'data');
  stdout += first;
  child.kill('SIGINT');
  await closed;
  lines = readFileSync(file, 'utf8').trimEnd().split('\n');
});
afterAll(() => rmSync(dir, { recursive: true, force: true }));

test('library stdout and stderr go to the file, the terminal only gets what the process prints itself', () => {
  expect(stdout).toBe('ready\n');
  expect(stderr).toBe('');
  expect(lines.some((l) => l.startsWith('[info] ') && l.includes('[fixture] token'))).toBe(true);
  expect(lines).toContain('[error] from a dependency');
});

test('the level comes from logLevel and the console method', () => {
  expect(lines.some((l) => l.includes('hidden'))).toBe(false);
  expect(lines.filter((l) => l.startsWith('[error] ')).length).toBe(2);
});

test('logs carry their context and GitHub tokens never reach the file', () => {
  const text = lines.join('\n');
  expect(text).toContain('"repo":"a/b","epic":7');
  expect(text).toContain('"executionId":"e1","stage":"fix","round":2');
  expect(text).toContain('[redacted] here');
  expect(text).not.toMatch(/ghp_|ghs_|github_pat_/);
});

test('errors keep the original stack', () => {
  const entry = lines.find((l) => l.includes('[fixture] failed'))!;
  const parsed = JSON.parse(entry.slice('[error] '.length));
  expect(parsed.error).toBe('boom');
  expect(parsed.stack).toContain('Error: boom\n    at ');
  expect(parsed.stack).toContain('logger.fixture.ts');
});

test('after SIGINT the file holds everything emitted so far, whole lines and no gaps', () => {
  const ticks = lines.filter((l) => l.includes('[fixture] tick')).map((l) => JSON.parse(l.slice('[info] '.length)).seq);
  expect(ticks.length).toBeGreaterThanOrEqual(50);
  expect(ticks).toEqual(ticks.map((_, i) => i + 1));
  for (const l of lines) expect(l).toMatch(/^\[(info|error)\] /);
});

test('an execution output redacts a token split across two chunks and keeps the unfinished line until flush', () => {
  const root = mkdtempSync(join(tmpdir(), 'carrier-out-'));
  const output = executionOutput(join(root, 'logs'), 'e1');
  const out = join(root, 'logs', 'executions', 'e1', 'stdout.log');
  output.write('stdout', 'before ghp_abcdef');
  output.write('stdout', '123456 after\nnext ghp_tail');
  expect(readFileSync(out, 'utf8')).toBe('before [redacted] after\n');
  output.flush();
  expect(readFileSync(out, 'utf8')).toBe('before [redacted] after\nnext [redacted]');
  rmSync(root, { recursive: true, force: true });
});

test('an execution output past maxBytes moves the stream to .1 and starts again; the next rotation replaces .1', () => {
  const root = mkdtempSync(join(tmpdir(), 'carrier-out-'));
  const output = executionOutput(join(root, 'logs'), 'e1', 40);
  const dir = join(root, 'logs', 'executions', 'e1');
  const out = join(dir, 'stdout.log');
  const line = (n: number) => `line ${n} 12345678\n`; // 16 bytes
  output.write('stdout', line(1) + line(2));
  expect(statSync(out).size).toBe(32);
  expect(existsSync(`${out}.1`)).toBe(false);
  output.write('stdout', line(3)); // 48 > 40: the block so far moves aside, whole lines
  expect(readFileSync(`${out}.1`, 'utf8')).toBe(line(1) + line(2));
  expect(readFileSync(out, 'utf8')).toBe(line(3));
  output.write('stdout', line(4)); // 32 <= 40: the new file is counted from zero, no rotation
  expect(readFileSync(out, 'utf8')).toBe(line(3) + line(4));
  expect(readFileSync(`${out}.1`, 'utf8')).toBe(line(1) + line(2));
  output.write('stdout', line(5)); // rotates again and the one before goes
  expect(readFileSync(`${out}.1`, 'utf8')).toBe(line(3) + line(4));
  expect(readFileSync(out, 'utf8')).toBe(line(5));
  expect(existsSync(`${out}.2`)).toBe(false);
  output.write('stderr', 'err\n');
  expect(existsSync(join(dir, 'stderr.log.1'))).toBe(false); // each stream counts its own size
  rmSync(root, { recursive: true, force: true });
});

test('a chunk bigger than maxBytes into an empty stream is written whole and rotates nothing', () => {
  const root = mkdtempSync(join(tmpdir(), 'carrier-out-'));
  const dir = join(root, 'logs', 'executions', 'e1');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'stdout.log.1'), 'kept\n');
  executionOutput(join(root, 'logs'), 'e1', 10).write('stdout', 'a line much longer than ten bytes\n');
  expect(readFileSync(join(dir, 'stdout.log.1'), 'utf8')).toBe('kept\n');
  expect(readFileSync(join(dir, 'stdout.log'), 'utf8')).toBe('a line much longer than ten bytes\n');
  rmSync(root, { recursive: true, force: true });
});

test('an execution output that reopens a run counts what the file already holds', () => {
  const root = mkdtempSync(join(tmpdir(), 'carrier-out-'));
  const first = executionOutput(join(root, 'logs'), 'e1', 20);
  first.write('stdout', 'aaaaaaaaaaaaaaa\n'); // 16 bytes
  const again = executionOutput(join(root, 'logs'), 'e1', 20);
  again.write('stdout', 'bbbbbbbbbbbbbbb\n');
  const out = join(root, 'logs', 'executions', 'e1', 'stdout.log');
  expect(readFileSync(`${out}.1`, 'utf8')).toBe('aaaaaaaaaaaaaaa\n');
  expect(readFileSync(out, 'utf8')).toBe('bbbbbbbbbbbbbbb\n');
  rmSync(root, { recursive: true, force: true });
});
