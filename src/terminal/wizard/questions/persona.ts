import { persona } from '../../../config/schema.ts';
import type { Ui } from '../../prompts/types.ts';
import type { Persona } from '../build-config.ts';

/** The persona of a role: first a choice (default, or set one; when editing, keep the current), so skipping reads as an answer; then a name and a prompt, each skippable by leaving it empty; when editing, empty keeps the current value and `-` clears it. The limits are the schema's. A flag answers ahead of time and, outside the limits, is an error naming it. */
export async function askPersona(ui: Ui, role: 'author' | 'reviewer' | 'lead reviewer', given: { name?: string; prompt?: string }, interactive: boolean, current?: Persona): Promise<Persona | undefined> {
  const roleName = role.split(' ').map((w) => `${w[0]!.toUpperCase()}${w.slice(1)}`).join(' ');
  const flagPrefix = role.replace(/\s+/g, '-');
  const field = async (key: 'name' | 'prompt', flag: string | undefined): Promise<string | undefined> => {
    const refusal = (value: string) => {
      const parsed = persona.shape[key].safeParse(value);
      return parsed.success ? undefined : parsed.error.issues[0]?.message;
    };
    if (flag !== undefined) {
      const problem = refusal(flag);
      if (problem !== undefined) throw new Error(`--${flagPrefix}-persona-${key}: ${problem}`);
      return flag.trim();
    }
    if (!interactive) return undefined;
    const kept = current?.[key];
    const answer = await ui.text({
      message: `${roleName} persona: ${key === 'name' ? 'give it a name' : 'describe how it behaves'}`,
      placeholder: `${key === 'name' ? 'a short name, e.g. Rex' : 'who it is and how it works'}; ${kept ? 'Enter keeps it, - clears it' : 'Enter to skip'}`,
      defaultValue: kept ?? '',
      validate: (value) => (value.trim() === '' ? undefined : value.trim() === '-' ? (kept ? undefined : 'empty to skip') : refusal(value)),
    });
    return answer.trim() === '-' && kept ? undefined : answer.trim() || undefined;
  };
  if (interactive && given.name === undefined && given.prompt === undefined) {
    const summary = current && [current.name, current.prompt && (current.prompt.length > 40 ? `${current.prompt.slice(0, 39)}…` : current.prompt)].filter(Boolean).join(' · ');
    const choice = await ui.select({
      message: `${roleName} persona`,
      options: [
        ...(current ? [{ value: 'keep', label: 'Keep the current one', hint: summary }] : []),
        { value: 'default', label: current ? 'Remove it' : 'Default', hint: 'no name, no extra instructions' },
        { value: 'set', label: current ? 'Edit it' : 'Give it a name and a way of behaving' },
      ],
      initialValue: current ? 'keep' : 'default',
    });
    if (choice === 'keep') return current;
    if (choice === 'default') return undefined;
  }
  const name = await field('name', given.name);
  const prompt = await field('prompt', given.prompt);
  return name || prompt ? { ...(name && { name }), ...(prompt && { prompt }) } : undefined;
}
