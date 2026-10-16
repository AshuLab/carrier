import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, expect, test } from 'vitest';

const main = join(import.meta.dirname, 'main.ts');
const dir = mkdtempSync(join(tmpdir(), 'carrier-cli-'));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const valid = {
  root: dir,
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { a: {}, b: {} },
  orchestratorProfile: 'a',
  agents: {
    author: { profile: 'a', provider: 'claude', model: 'm' },
    reviewer: { profile: 'b', provider: 'codex', model: 'm' },
  },
};

// Runs from another working directory on purpose: nothing may depend on cwd.
const run = (...args: string[]) => spawnSync(process.execPath, [main, ...args], { cwd: dir, encoding: 'utf8' });
const write = (name: string, content: unknown) => {
  const file = join(dir, name);
  writeFileSync(file, JSON.stringify(content));
  return file;
};

test('valid config prints the effective config and exits 0', () => {
  const result = run('--config', write('ok.json', valid));
  expect(result.status).toBe(0);
  expect(JSON.parse(result.stdout)).toMatchObject({ pollIntervalMinutes: 5, repos: valid.repos });
});

test('startup logs go to orchestrator/logs/orchestrator.log, not to the terminal', () => {
  const result = run('--config', write('log.json', { ...valid, logLevel: 'debug' }));
  expect(() => JSON.parse(result.stdout)).not.toThrow();
  expect(result.stderr).toBe('');
  expect(readFileSync(join(dir, 'orchestrator', 'logs', 'orchestrator.log'), 'utf8')).toContain('[info] {"message":"[cli] carrier started"');
});

test('prints the effective agents per repo', () => {
  const repos = [{ name: 'a/b', agents: { reviewer: { model: 'other' } } }, { name: 'c/d' }];
  const result = run('--config', write('eff.json', { ...valid, repos }));
  const printed = JSON.parse(result.stdout).repos;
  expect(printed[0].agents.reviewer).toEqual({ ...valid.agents.reviewer, model: 'other' });
  expect(printed[1]).toEqual({ name: 'c/d', agents: valid.agents });
});

test('a relative --config path resolves against the working directory', () => {
  write('rel.json', valid);
  expect(run('--config', 'rel.json').status).toBe(0);
});

test('missing --config exits non-zero with usage', () => {
  const result = run();
  expect(result.status).not.toBe(0);
  expect(result.stderr).toContain('Usage: carrier --config');
});

test('invalid config lists every error and exits non-zero', () => {
  const result = run('--config', write('bad.json', { ...valid, limits: { maxConcurrentEpics: 0 }, orchestratorProfile: 'x' }));
  expect(result.status).not.toBe(0);
  expect(result.stdout).toBe('');
  expect(result.stderr).toContain('limits.maxConcurrentEpics');
  expect(result.stderr).toContain('orchestratorProfile');
});

test('a second carrier on the same root reports it and exits non-zero without printing config', async () => {
  const config = write('busy.json', valid);
  const holder = spawn(process.execPath, [join(import.meta.dirname, '../storage/lock-holder.fixture.ts'), join(dir, 'orchestrator')]);
  try {
    await once(holder.stdout, 'data');
    const result = run('--config', config);
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain('already running');
    expect(result.stdout).toBe('');
  } finally {
    holder.kill();
  }
});

test('missing file exits non-zero', () => {
  expect(run('--config', join(dir, 'nope.json')).status).not.toBe(0);
});
