import { emitKeypressEvents } from 'node:readline';
import type { Key } from './ui-state.ts';

type KeyInput = NodeJS.ReadableStream & { isTTY?: boolean; setRawMode?: (on: boolean) => unknown; resume(): unknown; pause(): unknown };

/**
 * Reads single keys from the terminal. Raw mode means Ctrl+C is a key like any other (it no longer raises SIGINT),
 * so the caller has to treat it as a quit. Nothing happens without a terminal. Returns the stop function.
 */
export function startKeys(stdin: KeyInput, onKey: (key: Key) => void): () => void {
  if (!stdin.isTTY || stdin.setRawMode === undefined) return () => {};
  emitKeypressEvents(stdin);
  stdin.setRawMode(true);
  stdin.resume();
  const handler = (sequence: string | undefined, key: { name?: string; ctrl?: boolean } | undefined) => onKey({ name: key?.name, ctrl: key?.ctrl, sequence });
  stdin.on('keypress', handler);
  const restore = () => stdin.setRawMode?.(false); // also when the process dies on its own
  process.once('exit', restore);
  return () => {
    stdin.off('keypress', handler);
    process.removeListener('exit', restore);
    restore();
    stdin.pause();
  };
}
