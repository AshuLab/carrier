import { join } from 'node:path';
import { LogLevel } from '@ashulab/universal-logger';
import { enginePlacesOf } from '../../../config/places.ts';
import { installFileLogging } from '../../../logging/logger.ts';
import { initFlagsOf } from '../../wizard/flags.ts';
import { flagProblem } from '../../wizard/validate-flags.ts';
import { runInit } from '../../wizard/wizard.ts';
import { cancelled, makeClackUi, noPromptUi } from '../../prompts/clack.ts';
import { Cancelled } from '../../prompts/types.ts';
import type { Flags } from '../args.ts';
import { CliError } from '../cli-error.ts';
import { loadConfigFile } from '../config-file.ts';
import { runCommand } from './run.ts';

/** The guided setup. Returns the exit code, or undefined when "Start Carrier now?" was answered yes and it is running. */
export async function initCommand(flags: Flags, folder: string): Promise<number | undefined> {
  const initFlags = initFlagsOf(flags);
  const wrong = flagProblem(initFlags); // a flag that cannot work is refused before the Carrier folder is touched, not just before the wizard looks at the machine
  if (wrong !== undefined) throw new CliError(1, wrong);
  const ui = flags.yes || !process.stdin.isTTY ? noPromptUi : makeClackUi({ compact: true });
  installFileLogging(join(enginePlacesOf(folder).logs, 'orchestrator.log'), LogLevel.INFO); // the doctor's checks log through console: to the Carrier folder's log, not over the wizard
  let started;
  try {
    started = await runInit(
      initFlags,
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
  if (started.start) return void (await runCommand(started.config, folder, () => loadConfigFile(started.path, folder), { framed: true, configPath: started.path })); // the same process, until Ctrl+C
  return started.checks.some((c) => c.status === 'fail') ? 1 : 0;
}
