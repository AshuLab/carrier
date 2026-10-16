#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { defaults, loadConfig } from '../config/load.ts';
import { InstanceBusy, startCarrier } from './compose.ts';

// Not console.*: once logging is installed that goes to the log file, and these are for the person at the terminal.
const fail = (code: number, ...lines: string[]): never => {
  process.stderr.write(`${lines.join('\n')}\n`);
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
if (!result.ok) fail(1, `Invalid config ${file}:`, ...result.errors.map((e) => `  ${e.path}: ${e.message}`));
else {
  try {
    await startCarrier(result.config); // runs until Ctrl+C
  } catch (error) {
    if (error instanceof InstanceBusy) fail(1, error.message);
    fail(1, `carrier failed to start: ${error instanceof Error ? error.message : String(error)}`);
  }
}
