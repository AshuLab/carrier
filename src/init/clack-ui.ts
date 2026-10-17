import { styleText } from 'node:util';
import { autocomplete, autocompleteMultiselect, cancel, confirm, groupMultiselect, intro, isCancel, log, note, outro, select, spinner, text } from '@clack/prompts';
import type { Check } from '../doctor/doctor.ts';
import { Cancelled, type Ui } from './wizard.ts';

export { Cancelled };

const keep = <T>(value: T | symbol): T => {
  if (isCancel(value)) throw new Cancelled();
  return value as T;
};

const checkLine = ({ name, detail }: Check) => (detail ? `${name} — ${detail}` : name);
const fixLine = (fix: string) => log.message(styleText('dim', `→ ${fix}`));

/** One line per check, with its remedy under a failure. */
export function printCheck(check: Check) {
  if (check.status === 'ok') log.success(checkLine(check));
  else if (check.status === 'warn') log.warn(checkLine(check));
  else log.error(styleText('red', checkLine(check)));
  if (check.fix) fixLine(check.fix);
}

// Past this many options a plain list is a chore to scroll: type to filter instead.
const longList = 10;

export function makeClackUi(): Ui {
  // A check that takes a while (a token from Forge, a call to GitHub) shows a spinner until its result arrives.
  let spin: ReturnType<typeof spinner> | undefined;
  return {
    interactive: true,
    intro: (title) => intro(title),
    outro: (message) => outro(message),
    note: (message, title) => note(message, title),
    warn: (message) => log.warn(message),
    checkStart: (name) => {
      spin = spinner();
      spin.start(name);
    },
    check: (check) => {
      if (spin === undefined) return printCheck(check);
      if (check.status === 'fail') spin.error(checkLine(check));
      else spin.stop(checkLine(check));
      spin = undefined;
      if (check.fix) fixLine(check.fix);
    },
    text: async ({ validate, ...options }) =>
      (keep(await text({ ...options, validate: validate && ((value) => validate(value ?? options.defaultValue ?? '')) })) as string) || options.defaultValue || '',
    select: async (options) => {
      if (options.options.length > longList) return keep(await autocomplete({ message: options.message, options: options.options, initialValue: options.initialValue, placeholder: 'Type to filter…', maxItems: 8 } as Parameters<typeof autocomplete>[0])) as never;
      return keep(await select(options as Parameters<typeof select>[0])) as never;
    },
    confirm: async (message) => keep<boolean>(await confirm({ message })),
    multiselect: async ({ message, options, initialValues }) => {
      const groups = Object.values(options);
      if (groups.length === 1) return keep<string[]>(await autocompleteMultiselect({ message, options: groups[0]!, initialValues, required: true, placeholder: 'Type to filter…', maxItems: 8 }));
      return keep<string[]>(await groupMultiselect({ message, options, initialValues, required: true, maxItems: 12 }));
    },
  };
}

/** For `--yes` and for pipes: any question that was not answered by a flag is an error that names it. */
export const noPromptUi: Ui = {
  ...makeClackUi(),
  interactive: false,
  checkStart: () => {},
  check: printCheck,
  text: async ({ message, defaultValue }) => {
    if (defaultValue !== undefined) return defaultValue;
    throw new Error(`"${message}" needs an answer and there is no terminal to ask: pass it as a flag (carrier init --help)`);
  },
  select: async ({ message, initialValue }) => {
    if (initialValue !== undefined) return initialValue;
    throw new Error(`"${message}" needs an answer and there is no terminal to ask: pass it as a flag (carrier init --help)`);
  },
  confirm: async () => false,
  multiselect: async ({ message, initialValues }) => {
    if (initialValues?.length) return initialValues; // the repo of the current folder
    throw new Error(`"${message}" needs an answer and there is no terminal to ask: pass it as a flag (carrier init --help)`);
  },
};

export const clackUi = makeClackUi();

export const cancelled = () => cancel('✖  Cancelled');
