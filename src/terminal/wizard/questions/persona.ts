import { persona } from '../../../config/schema.ts';
import type { Ui } from '../../prompts/types.ts';
import type { Persona } from '../build-config.ts';

/** The persona of a role: a name and a prompt, each skippable by leaving it empty; when editing, empty keeps the current value and `-` clears it. The limits are the schema's. A flag answers ahead of time and, outside the limits, is an error naming it. */
export async function askPersona(ui: Ui, role: 'author' | 'reviewer', given: { name?: string; prompt?: string }, interactive: boolean, current?: Persona): Promise<Persona | undefined> {
  const field = async (key: 'name' | 'prompt', flag: string | undefined): Promise<string | undefined> => {
    const refusal = (value: string) => {
      const parsed = persona.shape[key].safeParse(value);
      return parsed.success ? undefined : parsed.error.issues[0]?.message;
    };
    if (flag !== undefined) {
      const problem = refusal(flag);
      if (problem !== undefined) throw new Error(`--${role}-persona-${key}: ${problem}`);
      return flag.trim();
    }
    if (!interactive) return undefined;
    const kept = current?.[key];
    const answer = await ui.text({
      message: `Persona of the ${role}: ${key === 'name' ? 'name' : 'prompt, how it behaves'} (${kept ? 'empty to keep it, - to clear it' : 'empty to skip'})`,
      placeholder: key === 'name' ? 'a name, one line' : 'who it is and how it behaves',
      defaultValue: kept ?? '',
      validate: (value) => (value.trim() === '' || (kept && value.trim() === '-') ? undefined : refusal(value)),
    });
    return answer.trim() === '-' && kept ? undefined : answer.trim() || undefined;
  };
  const name = await field('name', given.name);
  const prompt = await field('prompt', given.prompt);
  return name || prompt ? { ...(name && { name }), ...(prompt && { prompt }) } : undefined;
}
