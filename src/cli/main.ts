#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { createScopedLogger } from '@ashulab/universal-logger';
import { defaults, loadConfig } from '../config/load.ts';
import { resolveRepoConfig } from '../config/resolve.ts';
import { installFileLogging } from '../logging/logger.ts';
import { acquireLock } from '../storage/lock.ts';

const fail = (code: number, ...lines: string[]): never => {
  console.error(lines.join('\n'));
  process.exit(code);
};

const { values } = parseArgs({ options: { config: { type: 'string' } }, strict: false });
if (typeof values.config !== 'string') fail(2, 'Usage: carrier --config <path>');

const file = resolve(String(values.config));
let user: unknown;
try {
  user = JSON.parse(readFileSync(file, 'utf8'));
} catch (error) {
  fail(1, `Cannot read config ${file}: ${error instanceof Error ? error.message : String(error)}`);
}

const result = loadConfig(defaults, user);
if (!result.ok) {
  fail(1, `Invalid config ${file}:`, ...result.errors.map((e) => `  ${e.path}: ${e.message}`));
} else {
  // First side effect of startup: one instance per orchestrator/ folder.
  const orchestratorDir = join(result.config.root, 'orchestrator');
  const lock = acquireLock(orchestratorDir);
  if (lock.ok) process.on('exit', lock.release);
  else fail(1, `Another carrier instance is already running on ${orchestratorDir}`);

  const { config } = result;
  // From here on console.* goes to the log file; the terminal is for the config print and the panel.
  installFileLogging(join(orchestratorDir, 'logs', 'orchestrator.log'), config.logLevel);
  createScopedLogger('cli').info('carrier started', { root: config.root, repos: config.repos.length });
  const effective = { ...config, repos: config.repos.map((repo) => resolveRepoConfig(config, repo)) };
  process.stdout.write(`${JSON.stringify(effective, null, 2)}\n`);
}
