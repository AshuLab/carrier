import { enginePlacesOf } from '../../../config/places.ts';
import type { ControlSnapshot, EpicAdditions, PanelEpic } from '../../../status/types.ts';
import { cancelled, makeClackUi } from '../../prompts/clack.ts';
import { Cancelled, type Ui } from '../../prompts/types.ts';
import type { EpicTarget } from '../args.ts';
import { CliError } from '../cli-error.ts';
import { connectControl, ControlRefused, ControlUnreachable, type CarrierClient } from '../control-client.ts';

// The engine waits up to 30 seconds for the epic to start again before it refuses.
const RESTART_WAIT_MS = 40_000;

// The roles the command chooses an option for: an extra reviewer's option is the request's `extraReviewers`, which this command does not send yet.
const roleKeys = ['author', 'reviewer', 'lead'] as const;
const flagRoles = ['author', 'reviewer', 'lead'] as const;
type Chosen = Partial<Record<(typeof roleKeys)[number], string>>;
type Flags = Partial<Record<(typeof flagRoles)[number], string>> & { from?: 'ship' | 'review' | 'fix'; extraRounds?: number };

// What each refusal code means for the person, and what to do next.
export const refusals: Record<string, (target: string) => string> = {
  'epic.unknown': (target) => `Carrier does not know ${target}. Use the owner/repo#issue that carrier status shows.`,
  'resume.notStopped': (target) => `${target} is not stopped, so there is nothing to restart.`,
  'github.unavailable': () => 'GitHub did not answer, so nothing changed. Try again in a moment.',
  'resume.didNotRestart': () => 'The ready label is back on the issue, but the epic did not start within 30 seconds. The next check will take it.',
  'resume.optionUnknown': () => 'That account is not declared in providers.json. Use a name declared there.',
  'resume.roleUnknown': (target) => `${target} does not have that reviewer or lead. Name only the roles its configuration has.`,
  'resume.extraReviewerUnknown': (target) => `${target} does not have that extra reviewer. Name only the keys its configuration has.`,
  'resume.reviewersWithoutKey': (target) => `${target} was saved before its extra reviewers had names, so it cannot be restarted. Start it again from its issue.`,
  'resume.noPullRequest': (target) => `${target} has no pull request yet, so it can only be restarted from ship.`,
  'resume.extraRoundsNeedStage': () => '--extra-rounds needs --from review or --from fix: a restart from ship starts the rounds over.',
  'resume.extraRoundsNeedReviewLimit': (target) => `--extra-rounds grants rounds to an epic that stopped on the review limit, and ${target} stopped for another reason.`,
  'resume.pullRequestNotOpen': () => 'The epic\'s pull request is not open any more, so nothing was changed. Restart it from ship, or reopen the pull request.',
  'resume.pullRequestHeadChanged': () => 'The pull request has a different head than the one Carrier saved, so nothing was changed. Restart it with --from review to review the new head, or from ship to start over.',
};

/**
 * One question per role the epic has (the author, the reviewer and the lead, the last only with `reviewers`, which says the engine takes it),
 * with the role's current option preselected, and the option of the role of the execution that stopped the epic marked.
 * When that role ran out of usage its option is not preselected: two Enters would run the same option again.
 * Nothing is asked of an epic that has fewer than two options to choose from (or predates options).
 */
export async function askRestartOptions(epic: (Pick<PanelEpic, 'stage' | 'options'> & Partial<Pick<EpicAdditions, 'needsHumanKind'>>) | undefined, ui: Pick<Ui, 'select'>, reviewers = true): Promise<Chosen> {
  const options = epic?.options;
  if (!options || options.names.length < 2) return {};
  const failed = options.failed ?? (epic.stage === 'review' ? 'reviewer' : 'author');
  const roles = roleKeys.filter((role) => role === 'author' || role === 'reviewer' || (reviewers && options.lead !== undefined));
  const chosen: Chosen = {};
  for (const role of roles) {
    const current = options[role] ?? null;
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
    const named = flagRoles.filter((role) => flags[role] !== undefined);
    // an engine that does not list `resumeReviewerOptions` would only answer "invalid request"
    const reviewers = client.hello.capabilities.includes('resumeReviewerOptions');
    if (reviewers === false && named.includes('lead')) throw new CliError(1, 'The running Carrier is too old to restart the lead on an option: restart it to get --lead.');
    let chosen: Chosen = Object.fromEntries(named.map((role) => [role, flags[role]!]));
    if (named.length === 0 && process.stdin.isTTY && process.stdout.isTTY) {
      const { epics } = (await client.request('snapshot')) as ControlSnapshot;
      const epic = epics.find((e) => e.repo === repo && e.issue === issue);
      // Before any question: an epic the engine would refuse is not worth asking about.
      if (epic === undefined) throw new CliError(1, refusals['epic.unknown']!(`${repo}#${issue}`));
      if (epic.status !== 'needs_human') throw new CliError(1, refusals['resume.notStopped']!(`${repo}#${issue}`));
      try {
        chosen = await askRestartOptions(epic, makeClackUi({ compact: true }), reviewers);
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
    const code = error instanceof ControlRefused ? error.code : undefined;
    const words = error instanceof Error ? error.message : String(error);
    throw new CliError(1, (code === undefined ? undefined : refusals[code]?.(`${repo}#${issue}`)) ?? `Carrier refused: ${words}`);
  } finally {
    client.close();
  }
  process.stdout.write(`Restarted ${repo}#${issue}\n`);
  return 0;
}
