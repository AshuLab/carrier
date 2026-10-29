import { runInit } from '../../wizard/wizard.ts';
import { cancelled, makeClackUi, noPromptUi } from '../../prompts/clack.ts';
import { Cancelled } from '../../prompts/types.ts';
import type { Flags } from '../args.ts';
import { CliError } from '../cli-error.ts';
import { runCommand } from './run.ts';

/** The guided setup. Returns the exit code, or undefined when "Start Carrier now?" was answered yes and it is running. */
export async function initCommand(flags: Flags, folder: string): Promise<number | undefined> {
  const ui = flags.yes || !process.stdin.isTTY ? noPromptUi : makeClackUi({ compact: true });
  let started;
  try {
    started = await runInit(
      {
        repo: flags.repo,
        identities: flags.identities,
        authorProfile: flags['author-profile'],
        reviewerProfile: flags['reviewer-profile'],
        leadReviewerProfile: flags['lead-reviewer-profile'],
        author: flags.author,
        reviewer: flags.reviewer,
        leadReviewer: flags['lead-reviewer'],
        authorProvider: flags['author-provider'],
        reviewerProvider: flags['reviewer-provider'],
        leadReviewerProvider: flags['lead-reviewer-provider'],
        authorPersonaName: flags['author-persona-name'],
        authorPersonaPrompt: flags['author-persona-prompt'],
        reviewerPersonaName: flags['reviewer-persona-name'],
        reviewerPersonaPrompt: flags['reviewer-persona-prompt'],
        leadReviewerPersonaName: flags['lead-reviewer-persona-name'],
        leadReviewerPersonaPrompt: flags['lead-reviewer-persona-prompt'],
        out: flags.out,
        yes: flags.yes,
      },
      ui,
      undefined,
      folder,
    );
  } catch (error) {
    if (error instanceof Cancelled) {
      cancelled();
      return 0;
    }
    throw new CliError(1, error instanceof Error ? error.message : String(error));
  }
  if (started.start) return void (await runCommand(started.config, folder, { framed: true })); // the same process, until Ctrl+C
  return started.checks.some((c) => c.status === 'fail') ? 1 : 0;
}
