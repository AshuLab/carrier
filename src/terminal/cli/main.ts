#!/usr/bin/env node
// The entry point: read the command line, hand it to the command, turn a CliError into an exit code. Nothing else lives here.
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
      case 'status':
        if (configPath === undefined) throw noConfig('Usage: carrier status --config <path>');
        exit = await (await import('./commands/status.ts')).statusCommand(loadConfigFile(configPath));
        break;
      case 'stop':
      case 'pause':
      case 'resume':
      case 'check':
        if (configPath === undefined) throw noConfig(`Usage: carrier ${cli.command} --config <path>`);
        exit = await (await import('./commands/control.ts')).controlCommand(cli.command, loadConfigFile(configPath));
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
