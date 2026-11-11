import { efforts } from '../../../config/schema.ts';
import type { Ui } from '../../prompts/types.ts';
import type { Effort } from '../build-config.ts';

const unset = '\0unset';

/** How hard a role's model thinks. A flag answers ahead of time (outside the five levels it is an error naming it); otherwise a choice, starting from the current one; without a terminal, the current one is kept. */
export async function askEffort(ui: Ui, role: 'author' | 'reviewer' | 'lead reviewer', flag: string | undefined, interactive: boolean, current?: Effort): Promise<Effort | undefined> {
  if (flag !== undefined) {
    const effort = efforts.find((level) => level === flag);
    if (effort === undefined) throw new Error(`--${role.replace(/\s+/g, '-')}-effort "${flag}": expected ${efforts.join(', ')}`);
    return effort;
  }
  if (!interactive) return current;
  const choice = await ui.select<string>({
    message: `Effort for the ${role}`,
    options: [{ value: unset, label: "The CLI's own", hint: 'no effort is passed' }, ...efforts.map((level) => ({ value: level, label: level }))],
    initialValue: current ?? unset,
  });
  return efforts.find((level) => level === choice);
}
