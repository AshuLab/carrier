import { extraReviewerName, slug } from '../../../config/schema.ts';
import type { Ui } from '../../prompts/types.ts';

/** Why a name cannot be an extra reviewer's, or undefined: it is the schema's (one line of 1 to 40 characters) and no earlier reviewer of the config has it, compared without case. */
export const nameProblem = (value: string, others: string[]) => {
  const parsed = extraReviewerName.safeParse(value);
  if (!parsed.success) return value.trim() === '' ? 'a name is required' : parsed.error.issues[0]?.message;
  return others.some((other) => other.toLowerCase() === parsed.data.toLowerCase()) ? 'another extra reviewer already has that name' : undefined;
};

/** What an extra reviewer is called, shown by the app and the one thing its key is derived from. Required, with no suggestion (the file's own name when editing): a blank or taken answer asks again. */
export async function askExtraName(ui: Ui, others: string[], current?: string): Promise<string> {
  for (;;) {
    const answer = await ui.text({
      message: 'What is this extra reviewer called?',
      placeholder: 'e.g. Security API',
      ...(current !== undefined && { defaultValue: current }),
      validate: (value) => nameProblem(value, others),
    });
    if (nameProblem(answer, others) === undefined) return answer.trim();
    ui.warn(`${nameProblem(answer, others)}: try another name`);
  }
}

/** What the extra reviewer looks at: a label, any slug, `general` to start with. */
export async function askExtraType(ui: Ui, current = 'general'): Promise<string> {
  for (;;) {
    const answer = await ui.text({
      message: 'What does it look at? A type, like general, security or ux',
      defaultValue: current,
      validate: (value) => slug.safeParse(value.trim()).error?.issues[0]?.message,
    });
    const parsed = slug.safeParse(answer.trim());
    if (parsed.success) return parsed.data;
    ui.warn(`${parsed.error.issues[0]?.message}: try another type`);
  }
}
