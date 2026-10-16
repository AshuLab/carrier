import { accessSync, constants } from 'node:fs';
import { delimiter, join } from 'node:path';
import type { AgentTask } from '../execution/agent-runner.ts';

/** What to spawn for one execution. The env is the full child environment. */
export interface AgentCommand {
  bin: string;
  args: string[];
  cwd: string;
  env: Record<string, string>;
}

/** What one stdout line of a provider CLI tells the runner. */
export interface LineSignal {
  session?: string;
  authFailed?: true;
  sessionUnavailable?: true;
}

/** The part of the runner that is specific to one provider CLI; Claude and Codex each provide one. */
export interface ProviderAdapter {
  command(task: AgentTask, ctx: CommandContext): AgentCommand;
  parseLine(line: string): LineSignal | undefined;
}

export interface CommandContext {
  binary: string;
  /** GitHub token of this execution only; it goes to the child env and nowhere else. */
  githubToken: string;
  /** Commit author for bots: Forge does not export it outside its interactive mode. */
  gitIdentity?: { name: string; email: string };
  /** Environment the child inherits. */
  baseEnv: NodeJS.ProcessEnv;
}

/** Marker in the child's argv, so a later process finds the executions an earlier one left running. */
export const markerFor = (executionId: string) => `carrier-exec-${executionId}`;

export function childEnv({ githubToken, gitIdentity, baseEnv }: CommandContext): Record<string, string> {
  const identity = gitIdentity && {
    GIT_AUTHOR_NAME: gitIdentity.name,
    GIT_AUTHOR_EMAIL: gitIdentity.email,
    GIT_COMMITTER_NAME: gitIdentity.name,
    GIT_COMMITTER_EMAIL: gitIdentity.email,
  };
  const inherited = Object.entries(baseEnv).filter((e): e is [string, string] => e[1] !== undefined);
  return { ...Object.fromEntries(inherited), GH_TOKEN: githubToken, GITHUB_TOKEN: githubToken, ...identity };
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
