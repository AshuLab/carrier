import { efforts } from '../../../config/schema.ts';
import type { Ui } from '../../prompts/types.ts';
import type { Effort } from '../build-config.ts';
import { roleName, type Block } from '../roles.ts';

const unset = '\0unset';

/** What is wrong with an effort flag, naming it; undefined when it is one of the five levels. */
export const effortProblem = (slot: Block, flag: string) => (efforts.some((level) => level === flag) ? undefined : `--${slot}-effort "${flag}": expected ${efforts.join(', ')}`);

/** How hard a role's model thinks. A flag answers ahead of time (outside the five levels it is an error naming it); otherwise a choice, starting from the current one; without a terminal, the current one is kept. */
export async function askEffort(ui: Ui, slot: Block, flag: string | undefined, interactive: boolean, current?: Effort): Promise<Effort | undefined> {
  if (flag !== undefined) {
    const problem = effortProblem(slot, flag);
    if (problem !== undefined) throw new Error(problem);
    return efforts.find((level) => level === flag);
  }
  if (!interactive) return current;
  const choice = await ui.select<string>({
    message: `Effort for the ${roleName(slot)}`,
    options: [{ value: unset, label: "The CLI's own", hint: 'no effort is passed' }, ...efforts.map((level) => ({ value: level, label: level }))],
    initialValue: current ?? unset,
  });
  return efforts.find((level) => level === choice);
}
