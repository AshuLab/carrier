import type { Config } from '../../../config/schema.ts';
import { runDoctor, type DoctorDeps } from '../../../doctor/doctor.ts';
import { makeClackUi, noPromptUi, printCheck } from '../../prompts/clack.ts';

/** Lists every check (this command is asked for them) and returns the exit code: 1 when any failed. With `json`, stdout is the checks as one JSON array and nothing else. */
export async function doctorCommand(config: Config, folder: string, json = false, overrides: Partial<DoctorDeps> = {}): Promise<number> {
  if (json) {
    const checks = await runDoctor(config, folder, overrides); // no spinner or progress: the app reads stdout whole
    process.stdout.write(`${JSON.stringify(checks)}\n`);
    return checks.some((c) => c.status === 'fail') ? 1 : 0;
  }
  const ui = process.stdout.isTTY ? makeClackUi() : { ...noPromptUi, check: printCheck }; // a spinner per check only on a terminal
  const checks = await runDoctor(config, folder, overrides, ui.check, ui.checkStart);
  const failed = checks.filter((c) => c.status === 'fail').length;
  process.stdout.write(failed > 0 ? `\n${failed} of ${checks.length} checks failed\n` : `\nAll ${checks.length} checks passed\n`);
  return failed > 0 ? 1 : 0;
}
