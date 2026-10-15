#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { defaults, loadConfig } from '../config/load.ts';
import { resolveRepoConfig } from '../config/resolve.ts';

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
  const { config } = result;
  const effective = { ...config, repos: config.repos.map((repo) => resolveRepoConfig(config, repo)) };
  console.log(JSON.stringify(effective, null, 2));
}
