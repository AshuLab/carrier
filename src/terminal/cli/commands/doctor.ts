import type { Config } from '../../../config/schema.ts';
import { runDoctor } from '../../../doctor/doctor.ts';
import { makeClackUi, noPromptUi, printCheck } from '../../prompts/clack.ts';

/** Lists every check (this command is asked for them) and returns the exit code: 1 when any failed. */
export async function doctorCommand(config: Config, folder: string): Promise<number> {
  const ui = process.stdout.isTTY ? makeClackUi() : { ...noPromptUi, check: printCheck }; // a spinner per check only on a terminal
  const checks = await runDoctor(config, folder, {}, ui.check, ui.checkStart);
  const failed = checks.filter((c) => c.status === 'fail').length;
  process.stdout.write(failed > 0 ? `\n${failed} of ${checks.length} checks failed\n` : `\nAll ${checks.length} checks passed\n`);
  return failed > 0 ? 1 : 0;
}
