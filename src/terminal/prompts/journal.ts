import type { Option, Ui } from './types.ts';

/**
 * Esc and the recap's jump as one mechanism. The flow stays linear code; this wraps its `Ui`, remembers the answer to every question, and after `back` or `jump` the flow runs again from the top: each question that has an answer is answered from it and shows nothing, so the person lands on the dropped question with its old answer as the starting point.
 * A question is known by its block (`at`, a role slot or `repos`), its kind, its message and how many times that message came up in the block, so the same piece serves every role slot. The results of work that costs something (`busy`, and `once` for a step like adding a bot) are kept too and never run twice.
 * An answer whose option is gone (a profile the changed account no longer offers) is asked again.
 */
export function journaled(ui: Ui) {
  const answers = new Map<string, unknown>();
  const results = new Map<string, unknown>();
  const starting = new Map<string, unknown>(); // the dropped answers: where their questions start from
  let order: string[] = []; // the questions answered in this pass, in order
  let seen = new Map<string, number>();
  let block = '';
  let replaying = false;
  let dropped: Map<string, unknown> | undefined; // what the last jump took out, kept until its first question is asked for real or the pass is settled
  let firstLive: number | undefined; // how many questions were replayed before that first one: Esc there leaves the jump
  let held: (() => void)[] = []; // what the flow printed since the last replayed answer: shown only if the next question is asked for real

  const keyOf = (kind: string, message: string) => {
    const base = `${block}|${kind}|${message}`;
    const times = seen.get(base) ?? 0;
    seen.set(base, times + 1);
    return `${base}#${times}`;
  };
  const live = () => {
    replaying = false;
    for (const show of held) show();
    held = [];
  };
  const hold = (show: () => void) => (replaying ? void held.push(show) : show());
  const begin = () => {
    order = [];
    seen = new Map();
    block = '';
    replaying = true;
    held = [];
  };

  const ask = async <T>(kind: string, message: string, valid: (answer: unknown) => boolean, run: (start: T | undefined) => Promise<T>): Promise<T> => {
    const key = keyOf(kind, message);
    if (answers.has(key) && valid(answers.get(key))) {
      order.push(key);
      held = [];
      return answers.get(key) as T;
    }
    live();
    if (dropped !== undefined) firstLive ??= order.length;
    const start = starting.get(key);
    const answer = await run(valid(start) ? (start as T) : undefined);
    answers.set(key, answer);
    starting.delete(key);
    order.push(key);
    return answer;
  };
  const among = (options: Option<string>[], answer: unknown) => options.some((option) => option.value === answer);

  const once = <T>(label: string, work: () => T): T => {
    const key = keyOf('once', label);
    if (results.has(key)) return results.get(key) as T;
    live();
    const result = work();
    results.set(key, result);
    return result;
  };

  const wrapped: Ui = {
    ...ui,
    note: (message, title) => hold(() => ui.note(message, title)),
    warn: (message) => hold(() => ui.warn(message)),
    busy: async (message, work) => {
      const key = keyOf('busy', message);
      if (results.has(key)) return results.get(key) as Awaited<ReturnType<typeof work>>;
      live();
      const result = await ui.busy(message, work);
      results.set(key, result);
      return result;
    },
    text: (options) => ask('text', options.message, (answer) => typeof answer === 'string', (start) => ui.text(start === undefined ? options : { ...options, defaultValue: start })),
    select: (options) => ask('select', options.message, (answer) => among(options.options, answer), (start) => ui.select(start === undefined ? options : { ...options, initialValue: start })),
    confirm: (message, initialValue) => ask('confirm', message, (answer) => typeof answer === 'boolean', (start) => ui.confirm(message, start ?? initialValue)),
    multiselect: (options) =>
      ask(
        'multiselect',
        options.message,
        (answer) => Array.isArray(answer) && answer.every((value) => Object.values(options.options).some((group) => among(group, value))),
        (start) => ui.multiselect(start === undefined ? options : { ...options, initialValues: start }),
      ),
  };

  return {
    ui: wrapped,
    once,
    /** The block the next questions belong to. */
    at: (name: string) => void (block = name),
    /**
     * Esc: what to do with the pass that stopped on it, then start it again.
     * `recap`: the question was the first one asked for real after a jump, so the jump is abandoned with its block's answers back, and the flow ends where it did before.
     * `question`: drops the answer of the last question answered; it is asked again with that answer as its start.
     * `leave`: nothing is left to go back to.
     */
    back: (): 'recap' | 'question' | 'leave' => {
      if (dropped !== undefined && firstLive === order.length) {
        for (const [key, answer] of dropped) answers.set(key, answer);
        starting.clear();
        dropped = firstLive = undefined;
        begin();
        return 'recap';
      }
      const key = order.pop();
      if (key === undefined) return 'leave';
      starting.set(key, answers.get(key));
      answers.delete(key);
      begin();
      return 'question';
    },
    /** The recap's jump: drops the answers of one block, keeps every other, and starts the pass again. */
    jump: (name: string) => {
      dropped = new Map();
      firstLive = undefined;
      for (const key of [...answers.keys()].filter((k) => k.startsWith(`${name}|`))) {
        starting.set(key, answers.get(key));
        dropped.set(key, answers.get(key));
        answers.delete(key);
      }
      begin();
    },
    /** The pass reached the recap: a jump that was made is now part of the answers. */
    settled: () => void (dropped = firstLive = undefined),
  };
}
