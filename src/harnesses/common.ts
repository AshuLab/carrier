import { accessSync, constants } from 'node:fs';
import { delimiter, join } from 'node:path';
import type { AgentTask } from '../execution/agent-runner.ts';
import type { AgentEvent, EventState } from '../execution/events.ts';

/** What to spawn for one execution. The env is the full child environment. */
export interface AgentCommand {
  bin: string;
  args: string[];
  cwd: string;
  env: Record<string, string>;
}

/** What one stdout line of a harness CLI tells the runner. */
export interface LineSignal {
  session?: string;
  authFailed?: true;
  sessionUnavailable?: true;
}

/** The part of the runner that is specific to one harness CLI; each harness (Claude, Codex, Antigravity) provides one. */
export interface HarnessAdapter {
  command(task: AgentTask, ctx: CommandContext): AgentCommand;
  parseLine(line: string): LineSignal | undefined;
  /** Zero or more events for one stdout line. Never throws; a line it does not know gives []. Absent until the harness has a parser. */
  parseEvents?(line: string, state: EventState): AgentEvent[];
}

export interface CommandContext {
  binary: string;
  /** GitHub token of this execution only; it goes to the child env and nowhere else. */
  githubToken: string;
  /** Commit author for bots: Forge does not export it outside its interactive mode. */
  gitIdentity?: { name: string; email: string };
  /** Forge agent of a forge profile; git asks `agent-forge` for a fresh token with it. A name, not a secret. */
  forgeAgent?: string;
  /** Environment the child inherits. */
  baseEnv: NodeJS.ProcessEnv;
}

/** Marker in the child's argv, so a later process finds the executions an earlier one left running. */
export const markerFor = (executionId: string) => `carrier-exec-${executionId}`;

// git over HTTPS ignores GH_TOKEN: it asks the user's credential helpers (on macOS the keychain, i.e. the person's own login),
// so without this every push and branch operation of a bot would be made as that person. The first entry empties the helper
// list; the second answers with the execution's token, read from the environment when git asks (the token is not in the value).
// For a Forge bot (CARRIER_FORGE_AGENT set; read as a variable, never pasted into this text) it asks `agent-forge` for a token
// minted now, since the one the run started with expires after about an hour; if Forge prints nothing or fails, the starting token.
// Only `get` answers: git's `store` and `erase` must not mint tokens for nothing.
const gitUsesToken =
  '!f() { [ "$1" = get ] || return 0; echo username=x-access-token; ' +
  't=$([ -n "$CARRIER_FORGE_AGENT" ] && agent-forge token --agent "$CARRIER_FORGE_AGENT" 2>/dev/null); ' +
  'echo "password=${t:-$GH_TOKEN}"; }; f';

export function childEnv({ githubToken, gitIdentity, forgeAgent, baseEnv }: CommandContext): Record<string, string> {
  const identity = gitIdentity && {
    GIT_AUTHOR_NAME: gitIdentity.name,
    GIT_AUTHOR_EMAIL: gitIdentity.email,
    GIT_COMMITTER_NAME: gitIdentity.name,
    GIT_COMMITTER_EMAIL: gitIdentity.email,
  };
  const inherited = Object.entries(baseEnv).filter((e): e is [string, string] => e[1] !== undefined);
  const env = Object.fromEntries(inherited);
  // Keeps the config entries the environment already had (GIT_CONFIG_COUNT) and adds ours after them.
  const first = Number.isInteger(Number(env.GIT_CONFIG_COUNT)) ? Number(env.GIT_CONFIG_COUNT) : 0;
  const credentialHelper = {
    GIT_CONFIG_COUNT: String(first + 2),
    [`GIT_CONFIG_KEY_${first}`]: 'credential.helper',
    [`GIT_CONFIG_VALUE_${first}`]: '',
    [`GIT_CONFIG_KEY_${first + 1}`]: 'credential.helper',
    [`GIT_CONFIG_VALUE_${first + 1}`]: gitUsesToken,
  };
  return { ...env, GH_TOKEN: githubToken, GITHUB_TOKEN: githubToken, ...credentialHelper, ...identity, ...(forgeAgent && { CARRIER_FORGE_AGENT: forgeAgent }) };
}

const isExecutable = (path: string) => {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
};

/**
 * The real CLI binary, never a wrapper: Superset puts wrappers under ~/.superset/bin ahead of the real one
 * on PATH (they add flags and trap signals), see docs/research/headless-agents.md.
 */
export function resolveBinary(name: string, path = process.env.PATH ?? '', executable = isExecutable): string {
  for (const dir of path.split(delimiter)) {
    if (dir === '' || dir.includes('/.superset/')) continue;
    if (executable(join(dir, name))) return join(dir, name);
  }
  throw new Error(`cannot find the real "${name}" binary on PATH`);
}
