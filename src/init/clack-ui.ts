import { styleText } from 'node:util';
import { autocompleteMultiselect, cancel, confirm, intro, isCancel, log, note, outro, select, text } from '@clack/prompts';
import type { Check } from '../doctor/doctor.ts';
import type { Ui } from './wizard.ts';

/** The user pressed Ctrl+C or Esc in a prompt: not an error, the caller exits quietly. */
export class Cancelled extends Error {}

const keep = <T>(value: T | symbol): T => {
  if (isCancel(value)) throw new Cancelled();
  return value as T;
};

export function printCheck({ name, status, detail }: Check) {
  const line = detail ? `${name} — ${detail}` : name;
  if (status === 'ok') log.success(line);
  else if (status === 'warn') log.warn(line);
  else log.error(styleText('red', line));
}

export const clackUi: Ui = {
  intro: (title) => intro(title),
  outro: (message) => outro(message),
  note: (message, title) => note(message, title),
  warn: (message) => log.warn(message),
  check: printCheck,
  text: async ({ validate, ...options }) =>
    (keep(await text({ ...options, validate: validate && ((value) => validate(value ?? options.defaultValue ?? '')) })) as string) || options.defaultValue || '',
  select: async (options) => keep(await select(options as Parameters<typeof select>[0])) as never,
  confirm: async (message) => keep<boolean>(await confirm({ message })),
  multiselect: async ({ message, options, initialValues }) => keep<string[]>(await autocompleteMultiselect({ message, options, initialValues, required: true, placeholder: 'Type to filter…', maxItems: 8 })),
};

/** For `--yes` and for pipes: any question that was not answered by a flag is an error that names it. */
export const noPromptUi: Ui = {
  ...clackUi,
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

export const cancelled = () => cancel('✖  Cancelled');
