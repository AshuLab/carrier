import { parseArgs } from 'node:util';
import { engineConfigPathOf } from '../../config/places.ts';
import { efforts } from '../../config/schema.ts';
import { localKinds } from '../../harnesses/local.ts';
import { harnessNames } from '../../harnesses/names.ts';
import { roleSlots, roleFlagSuffixes, type RoleSlot } from '../wizard/roles.ts';

export const commandNames = ['init', 'doctor', 'schema', 'start', 'status', 'watch', 'stop', 'pause', 'resume', 'check', 'reload', 'restart', 'recover', 'chat', 'chat-host', 'usage', 'config'] as const;
export type CommandName = (typeof commandNames)[number];

export const usage = () => `Usage: carrier --config <path>          run the orchestrator
       carrier start --config <path>     run it in the background, without a terminal
       carrier init [flags]              guided setup: writes the config and checks it
       carrier doctor --config <path> [--json]   check the config and what this machine needs (--json: the checks as a JSON array on stdout, for the app)
       carrier schema                    print the JSON Schema of the config
       carrier status                    show once what the running Carrier is doing (exit 1: not running)
       carrier watch                     the live panel of the running Carrier; q leaves it running (exit 1: not running)
       carrier stop|pause|resume|check   stop Carrier, pause or resume intake, look at GitHub now
       carrier reload                    make the running Carrier read engine.json and providers.json again (exit 1: not running, or a file is wrong)
       carrier restart <owner/name>#<issue> [--author <option>] [--reviewer <option>] [--reviewer-2 <option>] [--reviewer-3 <option>] [--reviewer-4 <option>] [--lead <option>] [--from <ship|review|fix>] [--extra-rounds <K>]   resume a stopped epic on the options you choose
       carrier recover <owner/name>#<issue>   continue a running epic whose agent is not alive, from where it really is
       carrier chat --workspace <folder> [--agent <name>]   talk to an agent in a folder (starts the chat host if needed)
       carrier chat --resume <id>        go on with a closed chat session, after the end of its transcript
       carrier chat --list [--archived]  list chat sessions (the archived ones with --archived)
       carrier chat --archive|--unarchive|--delete <id>   archive, unarchive or delete a chat session
       carrier chat --stop               stop the chat host
       carrier chat-host                 run the chat host in the foreground
       carrier usage [--json] [--refresh] [--days <7|14|30>] [--provider <all|claude|codex|agy|local>] [--source <all|epic|chat|external>]   live quotas and what was used (starts the chat host if needed)
       carrier config                    change a Carrier folder setting: one request as one line of JSON on standard input, the reply as one line on standard output (exit 1: refused, 2: not a request)
       carrier --version                 print the installed version

--config defaults to ${engineConfigPathOf()} (where init writes it) when that file exists.

restart: with no option flag it asks for each role in a terminal and keeps the current options without one. --author, --reviewer, --reviewer-2 to --reviewer-4 and --lead name an option
of the config here, not the <harness>:<model> of init.
restart --from review or fix keeps the epic's round, pull request and worktree and starts at that stage; ship (the default) starts over with the rounds reset.
restart --extra-rounds K, with --from review or fix, sets how many review rounds an epic that stopped on the review limit gets from its current one (default: limits.maxReviews).

init flags (each one skips its question; --yes never asks):
  --repo <owner/name>            repeat for several repos
  --orchestrator-profile <forge:<agent>|gh>   the orchestrator's GitHub profile
  --<role>[-profile|-provider|-effort|-persona-name|-persona-prompt|-failover] <value>   for every role: ${roleSlots.join(', ')}
      --<role> <harness>:<model>              harness: ${harnessNames.join(', ')}
      --<role>-profile <forge:<agent>|gh>
      --<role>-provider <${localKinds.join('|')}>
      --<role>-effort <level>                 level: ${efforts.join(', ')}
      --<role>-persona-name <text>   --<role>-persona-prompt <text>
      --<role>-failover <account>[:<model>]   repeat for up to two steps, in order; the account is one of this Mac or providers.json
      reviewer-2 to reviewer-4 are the extra reviewers, in order: --reviewer-3 needs --reviewer-2
  --out <path>                   default is the --config default above
  --yes                          no questions (needs --repo); overwrite the output file; the author and the reviewer take the first of each agent found (claude for the author and codex for the reviewer when both exist)`;

/** What `--<role>`, `--<role>-profile` and the rest of a role's flags are, from the table of slots. `--reviewer-2` to `--reviewer-4` come from it too: strings in `restart`, where they name an option of the config. */
const roleOptions = Object.fromEntries(
  roleSlots.flatMap((slot) => [...roleFlagSuffixes.map((suffix) => [`${slot}${suffix}`, { type: 'string' }]), [`${slot}-failover`, { type: 'string', multiple: true }]]),
) as { [Name in `${RoleSlot}${(typeof roleFlagSuffixes)[number]}`]: { readonly type: 'string' } } & { [Name in `${RoleSlot}-failover`]: { readonly type: 'string'; readonly multiple: true } };

const options = {
  ...roleOptions,
  config: { type: 'string' },
  repo: { type: 'string', multiple: true },
  'orchestrator-profile': { type: 'string' },
  lead: { type: 'string' },
  from: { type: 'string' },
  'extra-rounds': { type: 'string' },
  out: { type: 'string' },
  yes: { type: 'boolean' },
  json: { type: 'boolean' },
  list: { type: 'boolean' },
  stop: { type: 'boolean' },
  workspace: { type: 'string' },
  agent: { type: 'string' },
  resume: { type: 'string' },
  archived: { type: 'boolean' },
  archive: { type: 'string' },
  unarchive: { type: 'string' },
  delete: { type: 'string' },
  refresh: { type: 'boolean' },
  days: { type: 'string' },
  provider: { type: 'string' },
  source: { type: 'string' },
  help: { type: 'boolean', short: 'h' },
  version: { type: 'boolean', short: 'v' },
} as const;

export type Flags = ReturnType<typeof parseArgs<{ options: typeof options; allowPositionals: true }>>['values'];
/** What `restart` and `recover` act on, from `owner/name#N`. */
export type EpicTarget = { repo: string; issue: number };
export type Parsed = { ok: true; command: CommandName | undefined; flags: Flags; target?: EpicTarget } | { ok: false; message: string };

const resumeStages: string[] = ['ship', 'review', 'fix'];
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
  if (command === 'restart' || command === 'recover') {
    const match = extra.length === 1 ? targetPattern.exec(extra[0]!) : null;
    const repo = match?.[1];
    if (!match || repo!.split('/').some((part) => part === '.' || part === '..') || !Number.isSafeInteger(Number(match[2]))) return { ok: false, message: `${command} takes one epic as owner/name#N, for example AshuLab/carrier#12` };
    if (command === 'restart' && parsed.values.from !== undefined && !resumeStages.includes(parsed.values.from)) return { ok: false, message: `--from takes ${resumeStages.join(', ')}` };
    const rounds = parsed.values['extra-rounds'];
    if (command === 'restart' && rounds !== undefined && !/^[1-9]\d{0,8}$/.test(rounds)) return { ok: false, message: '--extra-rounds takes a positive whole number' };
    return { ok: true, command, flags: parsed.values, target: { repo: repo!, issue: Number(match[2]) } };
  }
  if (extra.length > 0 || (command !== undefined && !(commandNames as readonly string[]).includes(command))) return { ok: false, message: `Unknown command: ${parsed.positionals.join(' ')}` };
  return { ok: true, command: command as CommandName | undefined, flags: parsed.values };
}
