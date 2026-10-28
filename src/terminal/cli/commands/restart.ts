import { join } from 'node:path';
import type { Config } from '../../../config/schema.ts';
import type { PanelEpic, PanelSnapshot } from '../../../status/types.ts';
import { cancelled, makeClackUi } from '../../prompts/clack.ts';
import { Cancelled, type Ui } from '../../prompts/types.ts';
import type { EpicTarget } from '../args.ts';
import { CliError } from '../cli-error.ts';
import { connectControl, ControlUnreachable, type CarrierClient } from '../control-client.ts';

// The engine waits up to 30 seconds for the epic to start again before it refuses.
const RESTART_WAIT_MS = 40_000;

type Chosen = { author?: string; reviewer?: string };

/**
 * One question per role with the role's current option preselected, and the option of the role that stopped the epic marked.
 * Nothing is asked of an epic that has fewer than two options to choose from (or predates options).
 */
export async function askOptions(epic: Pick<PanelEpic, 'stage' | 'options'> | undefined, ui: Pick<Ui, 'select'>): Promise<Chosen> {
  const options = epic?.options;
  if (!options || options.names.length < 2) return {};
  const failed = epic.stage === 'review' ? 'reviewer' : 'author';
  const chosen: Chosen = {};
  for (const role of ['author', 'reviewer'] as const) {
    const current = options[role];
    chosen[role] = await ui.select({
      message: `Option for the ${role}`,
      initialValue: current ?? undefined,
      options: options.names.map((name) => ({ value: name, label: name, ...(name === current && { hint: role === failed ? 'current, failed' : 'current' }) })),
    });
  }
  return chosen;
}

/** `carrier restart <owner/repo>#<issue>`: resumes a stopped epic over the control socket. Returns the exit code. */
export async function restartCommand(config: Config, { repo, issue }: EpicTarget, flags: Chosen): Promise<number> {
  const path = join(config.root, 'orchestrator', 'control.sock');
  let client: CarrierClient;
  try {
    client = await connectControl(path, { timeoutMs: RESTART_WAIT_MS });
  } catch (error) {
    if (error instanceof ControlUnreachable === false) throw error;
    if (error.reason === 'incompatible') throw new CliError(2, 'The running Carrier speaks a protocol this command does not (it expects 1). Update one of them.');
    if (error.reason === 'no-answer') throw new CliError(1, `Carrier does not answer on ${path}`);
    throw new CliError(1, 'Carrier is not running');
  }
  try {
    if (client.hello.capabilities.includes('agentOptions') === false) throw new CliError(1, 'The running Carrier is too old to restart an epic on a chosen option (it lacks the agentOptions capability). Update it.');
    let chosen: Chosen = { ...(flags.author && { author: flags.author }), ...(flags.reviewer && { reviewer: flags.reviewer }) };
    if (flags.author === undefined && flags.reviewer === undefined && process.stdin.isTTY && process.stdout.isTTY) {
      const { epics } = (await client.request('snapshot')) as PanelSnapshot;
      try {
        chosen = await askOptions(epics.find((e) => e.repo === repo && e.issue === issue), makeClackUi({ compact: true }));
      } catch (error) {
        if (error instanceof Cancelled === false) throw error;
        cancelled();
        return 0;
      }
    }
    await client.request('resumeEpic', { repo, issue, ...chosen });
  } catch (error) {
    if (error instanceof CliError) throw error;
    if (error instanceof ControlUnreachable) throw new CliError(1, `Carrier does not answer on ${path}`);
    throw new CliError(1, `Carrier refused: ${error instanceof Error ? error.message : String(error)}`);
  } finally {
    client.close();
  }
  process.stdout.write(`Restarted ${repo}#${issue}\n`);
  return 0;
}
