#!/usr/bin/env node
// The entry point: read the command line, hand it to the command, turn a CliError into an exit code. Nothing else lives here.
import { resolve } from 'node:path';
import { parseCli, usage } from './args.ts';
import { CliError } from './cli-error.ts';
import { configPathFor, loadConfigFile, noConfig } from './config-file.ts';

// Not console.*: once logging is installed that goes to the log file, and these are for the person at the terminal.
const fail = (code: number, ...lines: string[]): never => {
  process.stderr.write(`${lines.join('\n')}\n`);
  process.exit(code);
};

const cli = parseCli(process.argv.slice(2));
if (!cli.ok) fail(2, cli.message, '', usage());
else if (cli.flags.help) {
  process.stdout.write(`${usage()}\n`);
  process.exit(0);
} else {
  try {
    const configPath = configPathFor(cli.flags.config);
    let exit: number | undefined;
    switch (cli.command) {
      case 'schema':
        (await import('./commands/schema.ts')).schemaCommand();
        break;
      case 'init':
        exit = await (await import('./commands/init.ts')).initCommand(cli.flags);
        break;
      case 'doctor':
        if (configPath === undefined) throw noConfig('Usage: carrier doctor --config <path>');
        exit = await (await import('./commands/doctor.ts')).doctorCommand(loadConfigFile(configPath));
        break;
      case 'start':
        if (configPath === undefined) throw noConfig('Usage: carrier start --config <path>');
        exit = await (await import('./commands/start.ts')).startCommand(loadConfigFile(configPath), resolve(configPath));
        break;
      case 'status':
        if (configPath === undefined) throw noConfig('Usage: carrier status --config <path>');
        exit = await (await import('./commands/status.ts')).statusCommand(loadConfigFile(configPath));
        break;
      case 'watch':
        if (configPath === undefined) throw noConfig('Usage: carrier watch --config <path>');
        exit = await (await import('./commands/watch.ts')).watchCommand(loadConfigFile(configPath));
        break;
      case 'stop':
      case 'pause':
      case 'resume':
      case 'check':
        if (configPath === undefined) throw noConfig(`Usage: carrier ${cli.command} --config <path>`);
        exit = await (await import('./commands/control.ts')).controlCommand(cli.command, loadConfigFile(configPath));
        break;
      case 'restart':
        if (configPath === undefined) throw noConfig('Usage: carrier restart <owner/name>#<issue> --config <path>');
        exit = await (await import('./commands/restart.ts')).restartCommand(loadConfigFile(configPath), cli.target!, { author: cli.flags.author, reviewer: cli.flags.reviewer });
        break;
      case 'chat':
      case 'chat-host':
        // the chat runs from the Carrier folder alone (ADR 0016), not from an engine config
        if (cli.flags.config !== undefined) throw new CliError(2, `carrier ${cli.command} takes no --config: it runs from the Carrier folder (CARRIER_HOME, else ~/.carrier)`);
        if (cli.command === 'chat') exit = await (await import('./commands/chat.ts')).chatCommand(cli.flags);
        else await (await import('./commands/chat-host.ts')).chatHostCommand(); // runs until stopped
        break;
      default:
        if (configPath === undefined) throw noConfig(usage(), '');
        await (await import('./commands/run.ts')).runCommand(loadConfigFile(configPath)); // runs until Ctrl+C
    }
    if (exit !== undefined) process.exit(exit); // otherwise the command keeps the process alive (running), or has nothing left to do
  } catch (error) {
    if (error instanceof CliError) fail(error.code, ...error.lines);
    throw error;
  }
}
