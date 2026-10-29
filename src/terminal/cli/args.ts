import { parseArgs } from 'node:util';
import { defaultConfigPath } from '../../config/default-path.ts';

export const commandNames = ['init', 'doctor', 'schema', 'start', 'status', 'watch', 'stop', 'pause', 'resume', 'check', 'restart', 'chat', 'chat-host'] as const;
export type CommandName = (typeof commandNames)[number];

export const usage = () => `Usage: carrier --config <path>          run the orchestrator
       carrier start --config <path>     run it in the background, without a terminal
       carrier init [flags]              guided setup: writes the config and checks it
       carrier doctor --config <path>    check the config and what this machine needs
       carrier schema                    print the JSON Schema of the config
       carrier status                    show once what the running Carrier is doing (exit 1: not running)
       carrier watch                     the live panel of the running Carrier; q leaves it running (exit 1: not running)
       carrier stop|pause|resume|check --config <path>   stop Carrier, pause or resume intake, look at GitHub now
       carrier restart <owner/name>#<issue> [--author <option>] [--reviewer <option>]   resume a stopped epic on the options you choose
       carrier chat --workspace <folder> [--agent <name>]   talk to an agent in a folder (starts the chat host if needed)
       carrier chat --resume <id>        go on with a closed chat session, after the end of its transcript
       carrier chat --list [--archived]  list chat sessions (the archived ones with --archived)
       carrier chat --archive|--unarchive|--delete <id>   archive, unarchive or delete a chat session
       carrier chat --stop               stop the chat host
       carrier chat-host --config <path> run the chat host in the foreground
       carrier --version                 print the installed version

--config defaults to ${defaultConfigPath()} (where init writes it) when that file exists.

restart: with neither flag it asks for each role in a terminal and keeps the current options without one. --author and --reviewer name an option
of the config here, not the <harness>:<model> of init.

init flags (each one skips its question; --yes never asks):
  --repo <owner/name>            repeat for several repos
  --identities <separate|shared>  separate: a different identity per role (default); shared: your gh login for both
  --author-profile <forge:<agent>|gh>   --reviewer-profile <forge:<agent>|gh>   --lead-reviewer-profile <forge:<agent>|gh>
  --author <harness>:<model>            --reviewer <harness>:<model>            --lead-reviewer <harness>:<model>
  --author-provider <lmstudio|ollama>   --reviewer-provider <lmstudio|ollama>   --lead-reviewer-provider <lmstudio|ollama>
  --author-persona-name <text>   --reviewer-persona-name <text>   --lead-reviewer-persona-name <text>
  --author-persona-prompt <text> --reviewer-persona-prompt <text> --lead-reviewer-persona-prompt <text>
  --out <path>                   default is the --config default above
  --yes                          no questions; overwrite the output file (without --author and --reviewer, one claude option runs both roles)`;

const options = {
  config: { type: 'string' },
  repo: { type: 'string', multiple: true },
  identities: { type: 'string' },
  'author-profile': { type: 'string' },
  'reviewer-profile': { type: 'string' },
  'lead-reviewer-profile': { type: 'string' },
  author: { type: 'string' },
  reviewer: { type: 'string' },
  'lead-reviewer': { type: 'string' },
  'author-provider': { type: 'string' },
  'reviewer-provider': { type: 'string' },
  'lead-reviewer-provider': { type: 'string' },
  'author-persona-name': { type: 'string' },
  'author-persona-prompt': { type: 'string' },
  'reviewer-persona-name': { type: 'string' },
  'reviewer-persona-prompt': { type: 'string' },
  'lead-reviewer-persona-name': { type: 'string' },
  'lead-reviewer-persona-prompt': { type: 'string' },
  out: { type: 'string' },
  yes: { type: 'boolean' },
  list: { type: 'boolean' },
  stop: { type: 'boolean' },
  workspace: { type: 'string' },
  agent: { type: 'string' },
  resume: { type: 'string' },
  archived: { type: 'boolean' },
  archive: { type: 'string' },
  unarchive: { type: 'string' },
  delete: { type: 'string' },
  help: { type: 'boolean', short: 'h' },
  version: { type: 'boolean', short: 'v' },
} as const;

export type Flags = ReturnType<typeof parseArgs<{ options: typeof options; allowPositionals: true }>>['values'];
/** What `restart` acts on, from `owner/name#N`. */
export type EpicTarget = { repo: string; issue: number };
export type Parsed = { ok: true; command: CommandName | undefined; flags: Flags; target?: EpicTarget } | { ok: false; message: string };

const targetPattern = /^([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)#([1-9]\d*)$/;

/** The command line as data: no process exit, no output. A bad flag or an unknown command is `ok: false` with what to say. */
export function parseCli(argv: string[]): Parsed {
  let parsed;
  try {
    parsed = parseArgs({ args: argv, allowPositionals: true, options });
  } catch (error) {
    return { ok: false, message: error instanceof Error ? error.message : String(error) };
  }
  const [command, ...extra] = parsed.positionals;
  if (command === 'restart') {
    const match = extra.length === 1 ? targetPattern.exec(extra[0]!) : null;
    const repo = match?.[1];
    if (!match || repo!.split('/').some((part) => part === '.' || part === '..') || !Number.isSafeInteger(Number(match[2]))) return { ok: false, message: 'restart takes one epic as owner/name#N, for example AshuLab/carrier#12' };
    return { ok: true, command, flags: parsed.values, target: { repo: repo!, issue: Number(match[2]) } };
  }
  if (extra.length > 0 || (command !== undefined && !(commandNames as readonly string[]).includes(command))) return { ok: false, message: `Unknown command: ${parsed.positionals.join(' ')}` };
  return { ok: true, command: command as CommandName | undefined, flags: parsed.values };
}
