import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';

export type ForgeAgent = { name: string; label?: string };

/** Same lookup order as Agent Forge: $AGENT_FORGE_CONFIG, the global registry, then ./agents.json. */
export function forgeRegistryPath(env: NodeJS.ProcessEnv = process.env, cwd = process.cwd()): string | undefined {
  if (env.AGENT_FORGE_CONFIG) return resolve(env.AGENT_FORGE_CONFIG);
  const global = join(env.XDG_CONFIG_HOME || join(homedir(), '.config'), 'agent-forge', 'agents.json');
  if (existsSync(global)) return global;
  const local = resolve(cwd, 'agents.json');
  return existsSync(local) ? local : undefined;
}

/** The agents Forge knows about (names only, never keys). Empty when there is no registry; throws when it is unreadable. */
export function readForgeAgents(path = forgeRegistryPath()): ForgeAgent[] {
  if (path === undefined || !existsSync(path)) return [];
  const parsed: unknown = JSON.parse(readFileSync(path, 'utf8'));
  const agents = (parsed as { agents?: unknown }).agents;
  if (!Array.isArray(agents)) return [];
  return agents.flatMap((agent: { name?: unknown; label?: unknown }) =>
    typeof agent?.name === 'string' ? [{ name: agent.name, ...(typeof agent.label === 'string' ? { label: agent.label } : {}) }] : [],
  );
}
