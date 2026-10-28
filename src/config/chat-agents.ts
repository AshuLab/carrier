import type { Config } from './schema.ts';

type ChatAgentConfig = NonNullable<NonNullable<Config['chat']>['agents']>[string];
export type ChatAgent = ChatAgentConfig & { name: string };

const defaultChatAgents: Record<string, ChatAgentConfig> = { claude: { harness: 'claude' }, codex: { harness: 'codex' } };

/** The agents a chat can start with, in the order written; `claude` and `codex` when the config has no `chat` block. */
export const chatAgents = (config: Config): ChatAgent[] =>
  Object.entries(config.chat?.agents ?? defaultChatAgents).map(([name, agent]) => ({ name, ...agent }));
