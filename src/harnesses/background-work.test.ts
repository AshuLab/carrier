import { expect, test } from 'vitest';
import type { AgentTask } from '../execution/agent-runner.ts';
import { buildAgyCommand } from './agy.ts';
import { buildClaudeCommand } from './claude.ts';
import { buildCodexCommand } from './codex.ts';
import type { AgentCommand } from './common.ts';
import { harnessNames, type HarnessName } from './names.ts';

// A headless run ends with the agent's turn. A `ship` hands its slices to subagents and waits, so a CLI that ends the run
// (and stops them) while they work leaves the epic with no result. Each harness says here how its command prevents that;
// a new harness does not compile until it has an entry. Codex has none: no ceiling is known for it (docs/research/headless-agents.md, section 5).
const keepsBackgroundWorkAlive: Record<HarnessName, { build: typeof buildClaudeCommand; holds: (command: AgentCommand) => boolean }> = {
  claude: { build: buildClaudeCommand, holds: ({ env }) => env.CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS === '0' },
  agy: { build: buildAgyCommand, holds: ({ args }) => args[args.indexOf('--print-timeout') + 1] === '0' },
  codex: { build: buildCodexCommand, holds: () => true },
};

const task = (harness: HarnessName): AgentTask => ({ executionId: 'exec-1', repo: 'AshuLab/carrier', epic: 3, stage: 'ship', profile: 'author-bot', harness, model: 'm', workspace: '/work/carrier/3', resultPath: '/root/results/exec-1.json', timeoutMs: null, context: { previousSummaries: [] } });
const ctx = { binary: '/real/cli', githubToken: 'ghs_secret', baseEnv: { PATH: '/bin', HOME: '/h' } };

test.each(harnessNames)('the %s command does not let its CLI end the run while the agent has work in the background', (harness) => {
  const { build, holds } = keepsBackgroundWorkAlive[harness];
  expect(holds(build(task(harness), ctx))).toBe(true);
});
