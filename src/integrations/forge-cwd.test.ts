import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { forgeCwd } from './forge-cwd.ts';

let root: string;
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'carrier-forge-cwd-'));
});
afterEach(() => rmSync(root, { recursive: true, force: true }));

const origin = (cwd: string) => execFileSync('git', ['remote', 'get-url', 'origin'], { cwd, encoding: 'utf8' }).trim();

test('before the clone exists it is a stub repo whose origin is the repo, reused afterwards; once cloned, the clone itself', () => {
  const cwd = forgeCwd(root);
  const stub = cwd('AshuLab/carrier');
  expect(stub).toBe(join(root, 'orchestrator', 'forge-cwd', 'AshuLab', 'carrier'));
  expect(origin(stub)).toBe('https://github.com/AshuLab/carrier.git');
  expect(cwd('AshuLab/carrier')).toBe(stub);

  const clone = join(root, 'repos', 'AshuLab', 'carrier');
  mkdirSync(clone, { recursive: true });
  execFileSync('git', ['init', '-q'], { cwd: clone });
  expect(cwd('AshuLab/carrier')).toBe(clone);
});

test('rejects a repo that is not owner/name before touching the disk', () => {
  for (const bad of ['carrier', '../x', 'a/..', 'a/b/c']) expect(() => forgeCwd(root)(bad)).toThrow('invalid repo');
});
