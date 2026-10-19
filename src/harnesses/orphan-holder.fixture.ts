// Child process for host-runner.integration.test.ts: a "carrier" that starts one hanging agent and prints 'ready'
// once its session is known. The test then kills it with SIGKILL, leaving the agent orphaned.
import type { AgentTask } from '../execution/agent-runner.ts';
import { HostAgentRunner } from './host-runner.ts';

const [binary, workspace, harness = 'claude'] = process.argv.slice(2) as [string, string, AgentTask['harness']?];
const task: AgentTask = {
  executionId: `orphan-${harness}`,
  repo: 'AshuLab/carrier',
  epic: 3,
  stage: 'ship',
  profile: 'bot',
  harness,
  model: 'hang',
  workspace,
  resultPath: `${workspace}/result.json`,
  timeoutMs: null,
  context: { previousSummaries: [] },
};
const runner = new HostAgentRunner({ binaries: { [harness]: binary }, credentials: async () => ({ githubToken: 'ghs_holder' }) });
runner.run(task).onSession(() => console.log('ready'));
