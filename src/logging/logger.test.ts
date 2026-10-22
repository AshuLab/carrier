import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { afterAll, beforeAll, expect, test } from 'vitest';
import { executionOutput, taskContext } from './logger.ts';

test('universal-logger exposes createScopedLogger', () => {
  expect(typeof createScopedLogger).toBe('function');
});

test('taskContext derives the role from the stage and adds the round only when there is one', () => {
  const base = { repo: 'a/b', epic: 3, executionId: 'x' };
  expect(taskContext({ ...base, stage: 'review', round: 2 })).toEqual({ ...base, role: 'reviewer', stage: 'review', round: 2 });
  expect(taskContext({ ...base, stage: 'ship', round: null })).toEqual({ ...base, role: 'author', stage: 'ship' });
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
  const output = executionOutput(root, 'e1');
  const out = join(root, 'orchestrator', 'logs', 'executions', 'e1', 'stdout.log');
  output.write('stdout', 'before ghp_abcdef');
  output.write('stdout', '123456 after\nnext ghp_tail');
  expect(readFileSync(out, 'utf8')).toBe('before [redacted] after\n');
  output.flush();
  expect(readFileSync(out, 'utf8')).toBe('before [redacted] after\nnext [redacted]');
  rmSync(root, { recursive: true, force: true });
});
