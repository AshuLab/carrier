#!/usr/bin/env node
// The entry point: read the command line, hand it to the command, turn a CliError into an exit code. Nothing else lives here.
import { resolve } from 'node:path';
import { carrierHome } from '../../config/default-path.ts';
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
} else if (cli.flags.version) {
  process.stdout.write(`${(await import('../../control/server.ts')).version}\n`); // the value both hellos carry
  process.exit(0);
} else {
  try {
    const configPath = configPathFor(cli.flags.config);
    const folder = carrierHome(); // the one read of CARRIER_HOME; everything below is handed it
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
        exit = await (await import('./commands/doctor.ts')).doctorCommand(loadConfigFile(configPath), folder);
        break;
      case 'start':
        if (configPath === undefined) throw noConfig('Usage: carrier start --config <path>');
        loadConfigFile(configPath); // refuses a config the detached run would only fail on
        exit = await (await import('./commands/start.ts')).startCommand(folder, resolve(configPath));
        break;
      case 'status':
        exit = await (await import('./commands/status.ts')).statusCommand(folder);
        break;
      case 'watch':
        exit = await (await import('./commands/watch.ts')).watchCommand(folder);
        break;
      case 'stop':
      case 'pause':
      case 'resume':
      case 'check':
        exit = await (await import('./commands/control.ts')).controlCommand(cli.command, folder);
        break;
      case 'restart':
        exit = await (await import('./commands/restart.ts')).restartCommand(folder, cli.target!, { author: cli.flags.author, reviewer: cli.flags.reviewer });
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
        await (await import('./commands/run.ts')).runCommand(loadConfigFile(configPath), folder); // runs until Ctrl+C
    }
    if (exit !== undefined) process.exit(exit); // otherwise the command keeps the process alive (running), or has nothing left to do
  } catch (error) {
    if (error instanceof CliError) fail(error.code, ...error.lines);
    throw error;
  }
}
