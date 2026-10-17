import type { Ui } from '../../ui/types.ts';
import { tilde } from '../summary.ts';

const otherPath = '\0path';

/** Where the config goes: the global file, or a path typed. */
export async function askOut(ui: Ui, fallback: string) {
  const choice = await ui.select({
    message: 'Where should the config be saved?',
    options: [
      { value: fallback, label: tilde(fallback), hint: 'global: "carrier" finds it without --config' },
      { value: otherPath, label: 'Somewhere else…', hint: 'then use --config to point at it' },
    ],
    initialValue: fallback,
  });
  if (choice !== otherPath) return choice;
  return ui.text({ message: 'Path of the config file', placeholder: 'carrier.config.json', defaultValue: 'carrier.config.json' });
}
