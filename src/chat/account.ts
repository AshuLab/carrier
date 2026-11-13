import { carrierHome } from '../config/default-path.ts';
import { providersProblem, readProvidersFile, runtimeOf, type Providers } from '../config/providers.ts';
import { configDirVariable } from '../harnesses/names.ts';
import type { ChatAgent } from './config.ts';
import { ChatRefused } from './runner.ts';

/** `providers.json` as it is now: the chat host reads it each time it needs an account, so an edit reaches it with no restart (ADR 0020). */
export function readAccounts(folder = carrierHome()): Providers {
  const read = readProvidersFile(folder);
  if (read.ok === false) throw new ChatRefused(providersProblem(folder, read.errors));
  return read.providers;
}

/** The agents a chat can start with: a list, or a function that gives it each time it is asked. */
export type ChatAgents = ChatAgent[] | (() => ChatAgent[]);

/**
 * The agents of `chat.json` when it lists some; else one per account of `providers.json` but Antigravity's (a chat does not offer it), named as
 * the account. Read now, so an account added in Settings is there with no restart. A wrong `providers.json` is refused, naming the key.
 */
export function chatAgentsOf(configured: ChatAgent[] | undefined): ChatAgent[] {
  if (configured !== undefined) return configured;
  return Object.entries(readAccounts()).filter(([, account]) => account.harness !== 'agy').map(([name]) => ({ name, account: name }));
}

/** What a chat agent runs with: its account's harness, binary, compaction and launch arguments, and login, the login as the environment the CLI reads it from. Refuses, naming the account, one that is missing or Antigravity's. */
export function chatAccount(providers: Providers, agent: ChatAgent, env: NodeJS.ProcessEnv = {}) {
  const found = providers[agent.account];
  if (found === undefined) throw new ChatRefused(`The chat agent "${agent.name}" names the account "${agent.account}", which is not in providers.json`);
  if (found.harness === 'agy') throw new ChatRefused(`The chat agent "${agent.name}" names the account "${agent.account}", which is Antigravity's: a chat does not offer it`);
  const { harness, configDir } = found;
  const { command, ...launch } = runtimeOf(found);
  return { harness, command, launch, configDir, env: configDir === undefined ? env : { ...env, [configDirVariable[harness]]: configDir } };
}
