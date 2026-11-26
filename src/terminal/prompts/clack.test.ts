import { afterEach, expect, test, vi } from 'vitest';
import { makeClackUi } from './clack.ts';
import { Back, Cancelled } from './types.ts';

const cancelSymbol = vi.hoisted(() => Symbol.for('clack:cancel'));

// A prompt that ends on clack's cancel symbol after the given key was pressed, like clack does for Esc and for Ctrl+C.
const pressed = vi.hoisted(() => ({ key: { name: 'escape' } as { name: string; ctrl?: boolean } }));
vi.mock('@clack/prompts', async (importOriginal) => {
  const real = await importOriginal<typeof import('@clack/prompts')>();
  const ends = async () => {
    process.stdin.emit('keypress', undefined, pressed.key);
    return cancelSymbol;
  };
  return { ...real, isCancel: (value: unknown) => value === cancelSymbol, select: ends, text: ends, confirm: ends, multiselect: ends };
});

afterEach(() => process.stdin.removeAllListeners('keypress'));

const esc = { name: 'escape' };
const ctrlC = { name: 'c', ctrl: true };

test('with `back`, Esc in a prompt is Back and Ctrl+C is Cancelled', async () => {
  const ui = makeClackUi({ back: true });
  pressed.key = esc;
  await expect(ui.confirm('Go on?')).rejects.toBeInstanceOf(Back);
  await expect(ui.text({ message: 'Name' })).rejects.toBeInstanceOf(Back);
  pressed.key = ctrlC;
  await expect(ui.confirm('Go on?')).rejects.toBeInstanceOf(Cancelled);
  await expect(ui.select({ message: 'Pick', options: [{ value: 'a', label: 'A' }] })).rejects.toBeInstanceOf(Cancelled);
});

test('without `back` (restart, doctor, every other command) Esc still leaves: it is Cancelled', async () => {
  const ui = makeClackUi({ compact: true });
  pressed.key = esc;
  await expect(ui.select({ message: 'Pick', options: [{ value: 'a', label: 'A' }] })).rejects.toBeInstanceOf(Cancelled);
  await expect(ui.confirm('Go on?')).rejects.toBeInstanceOf(Cancelled);
  expect(process.stdin.listenerCount('keypress')).toBe(0); // no listener on standard input for them
});
