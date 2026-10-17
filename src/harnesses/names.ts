import type { LocalProvider } from './local.ts';

/** The agent CLIs Carrier can run; each is also the name of its binary. */
export const harnessNames = ['claude', 'codex', 'agy'] as const;
export type HarnessName = (typeof harnessNames)[number];

export const harnessLabel: Record<HarnessName, string> = { claude: 'Claude Code', codex: 'Codex', agy: 'Antigravity' };

/** Who serves the model when the config names no provider. */
export const nativeProvider: Record<HarnessName, string> = { claude: 'Anthropic', codex: 'OpenAI', agy: 'Antigravity' };

/** The local servers a harness can be pointed at. Antigravity has no setting for it (docs/research/antigravity.md). */
export const localProvidersOf: Record<HarnessName, readonly LocalProvider[]> = { claude: ['lmstudio', 'ollama'], codex: ['lmstudio', 'ollama'], agy: [] };
