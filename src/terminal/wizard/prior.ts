import { defaults, loadConfig } from '../../config/load.ts';
import type { Config } from '../../config/schema.ts';
import type { Identities, Role } from './build-config.ts';

export type Answered = Pick<Role, 'identity' | 'harness' | 'model' | 'provider' | 'persona'>;

/** What an existing config already says, to start from when editing it. */
export type Prior = { repos: string[]; identities: Identities; author: Answered; reviewer: Answered };

export function priorFrom(raw: unknown): Prior | undefined {
  const loaded = loadConfig(defaults, raw);
  if (!loaded.ok) return undefined;
  const { config } = loaded;
  const role = (r: Config['agents']['author']): Answered => {
    const { harness, model, provider } = config.agentOptions[r.option]!;
    return { identity: config.profiles[r.profile]!, harness, model, ...(provider && { provider }), ...(r.persona && { persona: r.persona }) };
  };
  return { repos: config.repos.map((r) => r.name), identities: config.identities, author: role(config.agents.author), reviewer: role(config.agents.reviewer) };
}
