import { persona } from '../../../config/schema.ts';
import type { Ui } from '../../prompts/types.ts';
import type { Persona } from '../build-config.ts';
import { roleName, type RoleSlot } from '../roles.ts';

/** The persona of a role: one "customise the persona?" (Enter says no, or yes when the file has one), and only a yes asks a name and a prompt, each skippable by leaving it empty; when editing, empty keeps the current value and `-` clears it. The limits are the schema's. A flag answers ahead of time and, outside the limits, is an error naming it. */
export async function askPersona(ui: Ui, slot: RoleSlot, given: { name?: string; prompt?: string }, interactive: boolean, current?: Persona): Promise<Persona | undefined> {
  const role = roleName(slot);
  const roleLabel = role.split(' ').map((word) => `${word[0]!.toUpperCase()}${word.slice(1)}`).join(' ');
  const field = async (key: 'name' | 'prompt', flag: string | undefined): Promise<string | undefined> => {
    const refusal = (value: string) => {
      const parsed = persona.shape[key].safeParse(value);
      return parsed.success ? undefined : parsed.error.issues[0]?.message;
    };
    if (flag !== undefined) {
      const problem = refusal(flag);
      if (problem !== undefined) throw new Error(`--${slot}-persona-${key}: ${problem}`);
      return flag.trim();
    }
    if (!interactive) return undefined;
    const kept = current?.[key];
    const answer = await ui.text({
      message: `${roleLabel} persona: ${key === 'name' ? 'give it a name' : 'describe how it behaves'}`,
      placeholder: `${key === 'name' ? 'a short name, e.g. Rex' : 'who it is and how it works'}; ${kept ? 'Enter keeps it, - clears it' : 'Enter to skip'}`,
      defaultValue: kept ?? '',
      validate: (value) => (value.trim() === '' ? undefined : value.trim() === '-' ? (kept ? undefined : 'empty to skip') : refusal(value)),
    });
    return answer.trim() === '-' && kept ? undefined : answer.trim() || undefined;
  };
  if (interactive && given.name === undefined && given.prompt === undefined && !(await ui.confirm(`Customise the ${role}'s persona?`, current !== undefined))) return undefined;
  const name = await field('name', given.name);
  const prompt = await field('prompt', given.prompt);
  return name || prompt ? { ...(name && { name }), ...(prompt && { prompt }) } : undefined;
}
