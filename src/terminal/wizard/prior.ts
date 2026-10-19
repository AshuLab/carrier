import { defaults, loadConfig } from '../../config/load.ts';
import type { Config } from '../../config/schema.ts';
import type { Role } from './build-config.ts';

export type Answered = Pick<Role, 'identity' | 'harness' | 'model' | 'provider'>;

/** What an existing config already says, to start from when editing it. */
export type Prior = { repos: string[]; author: Answered; reviewer: Answered };

export function priorFrom(raw: unknown): Prior | undefined {
  const loaded = loadConfig(defaults, raw);
  if (!loaded.ok) return undefined;
  const { config } = loaded;
  const role = (r: Config['agents']['author']): Answered => ({ identity: config.profiles[r.profile]!, harness: r.harness, model: r.model, ...(r.provider && { provider: r.provider }) });
  return { repos: config.repos.map((r) => r.name), author: role(config.agents.author), reviewer: role(config.agents.reviewer) };
}
