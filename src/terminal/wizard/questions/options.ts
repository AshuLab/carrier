import { basename } from 'node:path';
import { optionNamePattern } from '../../../config/schema.ts';
import type { LocalProvider } from '../../../harnesses/local.ts';
import type { HarnessName } from '../../../harnesses/names.ts';
import type { Ui } from '../../prompts/types.ts';
import { parseHarnessModel, parseProvider, type AgentOption, type Failover } from '../build-config.ts';
import type { InitDeps } from '../deps.ts';
import { optionLine } from '../summary.ts';
import { askAgentOption } from './agent.ts';

type Options = Record<string, AgentOption>;
type RoleName = 'author' | 'reviewer';

const uniqueName = (options: Options, base: string) => {
  let name = base;
  for (let n = 2; name in options; n += 1) name = `${base}-${n}`;
  return name;
};

/** Named after its harness and folder: `claude`, `claude-ashu-lab` for `~/.claude-ashu-lab`, `codex`. */
function suggestName(options: Options, option: AgentOption) {
  const folder = (option.configDir ? basename(option.configDir) : '').replace(/^\.+/, '');
  const raw = folder === '' ? option.harness : folder.startsWith(option.harness) ? folder : `${option.harness}-${folder}`;
  const slug = raw.toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 30);
  return uniqueName(options, optionNamePattern.test(slug) ? slug : option.harness);
}

const sameOption = (a: AgentOption, b: AgentOption) => a.harness === b.harness && a.model === b.model && a.provider === b.provider && a.configDir === b.configDir;

/** The option a `--author` or `--reviewer` flag declares: one that is already there, or a new one named after its harness (`<harness>-<role>` when that name is taken). */
export function declareFlagged(options: Options, role: RoleName, flag: string, providerFlag?: string): { options: Options; name: string } {
  const option: AgentOption = { ...parseHarnessModel(flag), ...(providerFlag && { provider: parseProvider(providerFlag) }) };
  const existing = Object.keys(options).find((name) => sameOption(options[name]!, option));
  if (existing !== undefined) return { options, name: existing };
  const name = uniqueName(options, option.harness in options ? `${option.harness}-${role}` : option.harness);
  return { options: { ...options, [name]: option }, name };
}

/** The Agent options section: adds options one at a time, after the ones already there, until the person has enough. At least one. */
export async function askOptions(ui: Ui, start: Options, installed: readonly HarnessName[], locals: Partial<Record<LocalProvider, string[]>>, deps: InitDeps): Promise<Options> {
  const there = Object.entries(start).map(([name, option]) => `${name}: ${optionLine(option)}`);
  ui.note(['A way to run an agent: a CLI, a model and, for Claude and Codex, a config folder (its login). Each role then picks one.', ...(there.length > 0 ? ['', 'Already there:', ...there] : [])].join('\n'), 'Agent options');
  let options = start;
  while (Object.keys(options).length === 0 || (await ui.confirm('Add another agent option?'))) {
    const option = await askAgentOption(ui, installed, Object.values(options).map((o) => o.harness), locals, deps);
    const name = (await ui.text({
      message: 'Name of this option',
      defaultValue: suggestName(options, option),
      validate: (v) => (!optionNamePattern.test(v.trim()) ? 'A lowercase word: letters, digits and hyphens, starting with a letter' : v.trim() in options ? 'Another option has this name' : undefined),
    })).trim();
    options = { ...options, [name]: option };
  }
  return options;
}

/** Which option runs a role, among the created ones; with only one there is nothing to choose. `current` is where it starts, then the first option that is not `other`'s (the author's, for the reviewer). */
export async function askRoleOption(ui: Ui, role: RoleName, options: Options, current?: string, other?: string): Promise<string> {
  const names = Object.keys(options);
  if (names.length === 1) return names[0]!;
  return ui.select({
    message: `Which option runs the ${role}?`,
    options: names.map((name) => ({ value: name, label: name, hint: optionLine(options[name]!) })),
    initialValue: [current, names.find((name) => name !== other)].find((name) => name !== undefined && name in options) ?? names[0]!,
  });
}

const done = '\0done';

/** With two or more options: whether to move a role to another option when its credits run out, and in which order. */
export async function askFailover(ui: Ui, options: Options): Promise<Failover | undefined> {
  const names = Object.keys(options);
  if (names.length < 2 || !(await ui.confirm('Turn failover on? A role that runs out of credits then moves to the next option you list, so its code can reach another provider.'))) return undefined;
  const order: string[] = [];
  while (order.length < names.length) {
    const pick = await ui.select({
      message: `Failover order: which option goes ${order.length === 0 ? 'first' : 'next'}?`,
      options: [...names.filter((name) => !order.includes(name)).map((name) => ({ value: name, label: name, hint: optionLine(options[name]!) })), ...(order.length > 0 ? [{ value: done, label: 'That is all' }] : [])],
    });
    if (pick === done) break;
    order.push(pick);
  }
  return { enabled: true, order };
}
