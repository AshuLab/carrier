import { parseArgs } from 'node:util';
import { defaultConfigPath } from '../../config/default-path.ts';

export const commandNames = ['init', 'doctor', 'schema', 'start', 'status', 'watch', 'stop', 'pause', 'resume', 'check'] as const;
export type CommandName = (typeof commandNames)[number];

export const usage = () => `Usage: carrier --config <path>          run the orchestrator
       carrier start --config <path>     run it in the background, without a terminal
       carrier init [flags]              guided setup: writes the config and checks it
       carrier doctor --config <path>    check the config and what this machine needs
       carrier schema                    print the JSON Schema of the config
       carrier status                    show once what the running Carrier is doing (exit 1: not running)
       carrier watch                     the live panel of the running Carrier; q leaves it running (exit 1: not running)
       carrier stop|pause|resume|check --config <path>   stop Carrier, pause or resume intake, look at GitHub now

--config defaults to ${defaultConfigPath()} (where init writes it) when that file exists.

init flags (each one skips its question; --yes never asks):
  --repo <owner/name>            repeat for several repos
  --identities <separate|shared>  separate: a different identity per role (default); shared: your gh login for both
  --author-profile <forge:<agent>|gh>   --reviewer-profile <forge:<agent>|gh>
  --author <harness>:<model>            --reviewer <harness>:<model>           harness: claude, codex or agy
  --author-provider <lmstudio|ollama>   --reviewer-provider <lmstudio|ollama>   the model runs on that local server
  --out <path>                   default is the --config default above
  --yes                          no questions; overwrite the output file`;

const options = {
  config: { type: 'string' },
  repo: { type: 'string', multiple: true },
  identities: { type: 'string' },
  'author-profile': { type: 'string' },
  'reviewer-profile': { type: 'string' },
  author: { type: 'string' },
  reviewer: { type: 'string' },
  'author-provider': { type: 'string' },
  'reviewer-provider': { type: 'string' },
  out: { type: 'string' },
  yes: { type: 'boolean' },
  help: { type: 'boolean', short: 'h' },
} as const;

export type Flags = ReturnType<typeof parseArgs<{ options: typeof options; allowPositionals: true }>>['values'];
export type Parsed = { ok: true; command: CommandName | undefined; flags: Flags } | { ok: false; message: string };

/** The command line as data: no process exit, no output. A bad flag or an unknown command is `ok: false` with what to say. */
export function parseCli(argv: string[]): Parsed {
  let parsed;
  try {
    parsed = parseArgs({ args: argv, allowPositionals: true, options });
  } catch (error) {
    return { ok: false, message: error instanceof Error ? error.message : String(error) };
  }
  const [command, ...extra] = parsed.positionals;
  if (extra.length > 0 || (command !== undefined && !(commandNames as readonly string[]).includes(command))) return { ok: false, message: `Unknown command: ${parsed.positionals.join(' ')}` };
  return { ok: true, command: command as CommandName | undefined, flags: parsed.values };
}
