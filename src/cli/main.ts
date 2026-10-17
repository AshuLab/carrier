#!/usr/bin/env node
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { createScopedLogger } from '@ashulab/universal-logger';
import { defaultConfigPath } from '../config/default-path.ts';
import { defaults, loadConfig } from '../config/load.ts';
import { userConfigJsonSchema } from '../config/json-schema.ts';
import { InstanceBusy, startCarrier } from './compose.ts';

// Not console.*: once logging is installed that goes to the log file, and these are for the person at the terminal.
const fail = (code: number, ...lines: string[]): never => {
  process.stderr.write(`${lines.join('\n')}\n`);
  process.exit(code);
};

const usage = `Usage: carrier --config <path>          run the orchestrator
       carrier init [flags]              guided setup: writes the config and checks it
       carrier doctor --config <path>    check the config and what this machine needs
       carrier schema                    print the JSON Schema of the config

--config defaults to ${defaultConfigPath()} (where init writes it) when that file exists.

init flags (each one skips its question; --yes never asks):
  --repo <owner/name>            repeat for several repos
  --author-profile <forge:<agent>|gh>   --reviewer-profile <forge:<agent>|gh>
  --author <claude|codex>:<model>       --reviewer <claude|codex>:<model>
  --out <path>                   default is the --config default above
  --yes                          no questions; overwrite the output file`;

function parse() {
  try {
    return parseArgs({
      allowPositionals: true,
      options: {
        config: { type: 'string' },
        repo: { type: 'string', multiple: true },
        'author-profile': { type: 'string' },
        'reviewer-profile': { type: 'string' },
        author: { type: 'string' },
        reviewer: { type: 'string' },
        out: { type: 'string' },
        yes: { type: 'boolean' },
        help: { type: 'boolean', short: 'h' },
      },
    });
  } catch (error) {
    return fail(2, error instanceof Error ? error.message : String(error), '', usage);
  }
}
const { values, positionals } = parse();
const [command, ...extra] = positionals;
if (values.help) {
  process.stdout.write(`${usage}\n`);
  process.exit(0);
}
if (extra.length > 0 || (command !== undefined && !['init', 'doctor', 'schema'].includes(command))) fail(2, `Unknown command: ${positionals.join(' ')}`, '', usage);

function loadFile(path: string) {
  const file = resolve(path);
  let user: unknown;
  try {
    user = JSON.parse(readFileSync(file, 'utf8'));
  } catch (error) {
    fail(1, `Cannot read config ${file}: ${error instanceof Error ? error.message : String(error)}`);
  }
  const result = loadConfig(defaults, user);
  if (!result.ok) fail(1, `Invalid config ${file}:`, ...result.errors.map((e) => `  ${e.path}: ${e.message}`));
  return result.ok ? result.config : fail(1);
}

// The explicit flag wins; otherwise the global file `carrier init` writes, if it is there.
const configPath = typeof values.config === 'string' ? values.config : existsSync(defaultConfigPath()) ? defaultConfigPath() : undefined;

if (command === 'schema') {
  process.stdout.write(`${JSON.stringify(userConfigJsonSchema(), null, 2)}\n`);
} else if (command === 'init') {
  const { Cancelled, cancelled, clackUi, noPromptUi } = await import('../init/clack-ui.ts');
  const { runInit } = await import('../init/wizard.ts');
  const ui = values.yes || !process.stdin.isTTY ? noPromptUi : clackUi;
  try {
    const { checks } = await runInit(
      { repo: values.repo, authorProfile: values['author-profile'], reviewerProfile: values['reviewer-profile'], author: values.author, reviewer: values.reviewer, out: values.out, yes: values.yes },
      ui,
    );
    process.exit(checks.some((c) => c.status === 'fail') ? 1 : 0);
  } catch (error) {
    if (error instanceof Cancelled) {
      cancelled();
      process.exit(0);
    }
    fail(1, error instanceof Error ? error.message : String(error));
  }
} else if (command === 'doctor') {
  if (configPath === undefined) fail(2, 'Usage: carrier doctor --config <path>', `No config at ${defaultConfigPath()}: run "carrier init" to create one.`);
  const config = loadFile(String(configPath));
  const { runDoctor } = await import('../doctor/doctor.ts');
  const { printCheck } = await import('../init/clack-ui.ts');
  const checks = await runDoctor(config, {}, printCheck);
  const failed = checks.filter((c) => c.status === 'fail').length;
  process.stdout.write(failed > 0 ? `\n${failed} of ${checks.length} checks failed\n` : `\nAll ${checks.length} checks passed\n`);
  process.exit(failed > 0 ? 1 : 0);
} else {
  if (configPath === undefined) fail(2, usage, '', `No config at ${defaultConfigPath()}: run "carrier init" to create one.`);
  const config = loadFile(String(configPath));
  try {
    await startCarrier(config); // runs until Ctrl+C
  } catch (error) {
    if (error instanceof InstanceBusy) fail(1, error.message);
    createScopedLogger('cli').error('startup failed', error); // logging is installed by now: the stack goes to the log file
    fail(1, `carrier failed to start: ${error instanceof Error ? error.message : String(error)}`);
  }
}
