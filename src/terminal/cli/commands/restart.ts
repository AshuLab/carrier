import { enginePlacesOf } from '../../../config/places.ts';
import type { ControlSnapshot, EpicAdditions, PanelEpic } from '../../../status/types.ts';
import { cancelled, makeClackUi } from '../../prompts/clack.ts';
import { Cancelled, type Ui } from '../../prompts/types.ts';
import type { EpicTarget } from '../args.ts';
import { CliError } from '../cli-error.ts';
import { connectControl, ControlUnreachable, type CarrierClient } from '../control-client.ts';

// The engine waits up to 30 seconds for the epic to start again before it refuses.
const RESTART_WAIT_MS = 40_000;

type Chosen = { author?: string; reviewer?: string };
type Flags = Chosen & { from?: 'ship' | 'review' | 'fix'; extraRounds?: number };

// What the engine's short refusal means for the person, and what to do next.
const refusals: Record<string, (target: string) => string> = {
  'unknown epic': (target) => `Carrier does not know ${target}. Use the owner/repo#issue that carrier status shows.`,
  'not stopped': (target) => `${target} is not stopped, so there is nothing to restart.`,
  'github unavailable': () => 'GitHub did not answer, so nothing changed. Try again in a moment.',
  'did not restart': () => 'The ready label is back on the issue, but the epic did not start within 30 seconds. The next check will take it.',
  'unknown option': () => 'That account is not declared in providers.json. Use a name declared there.',
  'no pull request': (target) => `${target} has no pull request yet, so it can only be restarted from ship.`,
  'extra rounds need a stage': () => '--extra-rounds needs --from review or --from fix: a restart from ship starts the rounds over.',
  'extra rounds need a review limit': (target) => `--extra-rounds grants rounds to an epic that stopped on the review limit, and ${target} stopped for another reason.`,
  'pull request not open': () => 'The epic\'s pull request is not open any more, so nothing was changed. Restart it from ship, or reopen the pull request.',
  'pull request head changed': () => 'The pull request has a different head than the one Carrier saved, so nothing was changed. Restart it from ship to start over.',
};

/**
 * One question per role with the role's current option preselected, and the option of the role that stopped the epic marked.
 * When that role ran out of usage its option is not preselected: two Enters would run the same option again.
 * Nothing is asked of an epic that has fewer than two options to choose from (or predates options).
 */
export async function askRestartOptions(epic: (Pick<PanelEpic, 'stage' | 'options'> & Partial<Pick<EpicAdditions, 'needsHumanKind'>>) | undefined, ui: Pick<Ui, 'select'>): Promise<Chosen> {
  const options = epic?.options;
  if (!options || options.names.length < 2) return {};
  const failed = epic.stage === 'review' ? 'reviewer' : 'author';
  const chosen: Chosen = {};
  for (const role of ['author', 'reviewer'] as const) {
    const current = options[role];
    const ranOut = role === failed && epic.needsHumanKind === 'usage_limit';
    chosen[role] = await ui.select({
      message: `Option for the ${role}`,
      initialValue: (ranOut ? options.names.find((name) => name !== current) : current) ?? undefined,
      options: options.names.map((name) => ({ value: name, label: name, ...(name === current && { hint: ranOut ? 'ran out' : role === failed ? 'current, failed' : 'current' }) })),
    });
  }
  return chosen;
}

/** `carrier restart <owner/repo>#<issue>`: resumes a stopped epic over the control socket. Returns the exit code. */
export async function restartCommand(folder: string, { repo, issue }: EpicTarget, flags: Flags): Promise<number> {
  const path = enginePlacesOf(folder).socket;
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
    // an engine that does not list `resumeFromStage` would only answer "invalid request"
    if ((flags.from !== undefined || flags.extraRounds !== undefined) && client.hello.capabilities.includes('resumeFromStage') === false) throw new CliError(1, 'The running Carrier is too old to resume from a stage: restart it to get --from.');
    let chosen: Chosen = { ...(flags.author && { author: flags.author }), ...(flags.reviewer && { reviewer: flags.reviewer }) };
    if (flags.author === undefined && flags.reviewer === undefined && process.stdin.isTTY && process.stdout.isTTY) {
      const { epics } = (await client.request('snapshot')) as ControlSnapshot;
      const epic = epics.find((e) => e.repo === repo && e.issue === issue);
      // Before any question: an epic the engine would refuse is not worth asking about.
      if (epic === undefined) throw new CliError(1, refusals['unknown epic']!(`${repo}#${issue}`));
      if (epic.status !== 'needs_human') throw new CliError(1, refusals['not stopped']!(`${repo}#${issue}`));
      try {
        chosen = await askRestartOptions(epic, makeClackUi({ compact: true }));
      } catch (error) {
        if (error instanceof Cancelled === false) throw error;
        cancelled();
        return 0;
      }
    }
    process.stdout.write(`Restarting ${repo}#${issue}…\n`); // the engine waits up to 30 seconds
    await client.request('resumeEpic', { repo, issue, ...chosen, ...(flags.from && { from: flags.from }), ...(flags.extraRounds !== undefined && { extraRounds: flags.extraRounds }) });
  } catch (error) {
    if (error instanceof CliError) throw error;
    if (error instanceof ControlUnreachable) throw new CliError(1, `Carrier does not answer on ${path}`);
    const reason = error instanceof Error ? error.message : String(error);
    throw new CliError(1, refusals[reason]?.(`${repo}#${issue}`) ?? `Carrier refused: ${reason}`);
  } finally {
    client.close();
  }
  process.stdout.write(`Restarted ${repo}#${issue}\n`);
  return 0;
}
