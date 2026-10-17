import type { Check } from '../doctor/doctor.ts';

/** The user said no (Ctrl+C, Esc, or declined the final question): not an error, the caller exits quietly. */
export class Cancelled extends Error {}

export type Option<T extends string> = { value: T; label: string; hint?: string; disabled?: boolean };

/** What the commands need from the terminal. The real one is clack (src/ui/clack.ts); tests script it. */
export interface Ui {
  /** False with `--yes` and without a terminal: nothing may be asked, and confirmations are skipped. */
  interactive: boolean;
  intro(title: string): void;
  outro(message: string): void;
  note(message: string, title: string): void;
  warn(message: string): void;
  /** A check is about to run (the UI may show a spinner); `check` follows with its result. */
  checkStart(name: string): void;
  check(check: Check): void;
  /** All the checks ran: `total` of them, `failed` of which failed. */
  checksEnd(total: number, failed: number): void;
  text(options: { message: string; placeholder?: string; defaultValue?: string; validate?: (value: string) => string | undefined }): Promise<string>;
  select<T extends string>(options: { message: string; options: Option<T>[]; initialValue?: T }): Promise<T>;
  confirm(message: string): Promise<boolean>;
  /** At least one. Several groups are shown as sections; a single group is a plain list to filter by typing. */
  multiselect(options: { message: string; options: Record<string, Option<string>[]>; initialValues?: string[] }): Promise<string[]>;
}
