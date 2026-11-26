import { Back, Cancelled } from './types.ts';

/** The part of a `keypress` event the decision needs. */
export type Key = { name?: string; ctrl?: boolean };

/** What a prompt that ended on its cancel symbol means, by the last key pressed: Esc goes back one question where the caller can (`goesBack`), anything else (Ctrl+C) leaves. Clack gives both keys the same cancel symbol, so the key is the only way to tell them apart. */
export const cancelFor = (key: Key | undefined, goesBack: boolean): Back | Cancelled => (goesBack && key?.name === 'escape' && key.ctrl !== true ? new Back() : new Cancelled());
