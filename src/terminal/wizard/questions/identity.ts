import type { Ui, Option } from '../../prompts/types.ts';
import { identityText, parseIdentity, type Identity } from '../build-config.ts';
import type { InitDeps } from '../deps.ts';
import type { ForgeAgent } from '../forge-registry.ts';

const addBot = '\0add';

/** Which GitHub identity a role acts as: a Forge bot or the person's own gh login. The same one as another role is allowed (they then share it); the default is one the other role does not have. */
export async function askIdentity(ui: Ui, role: 'author' | 'reviewer' | 'lead reviewer', forge: { agents: ForgeAgent[] }, readForge: () => void, login: string | undefined, other: Identity | undefined, deps: InitDeps, interactive: boolean, current?: Identity): Promise<Identity> {
  for (;;) {
    const options: Option<string>[] = [
      ...forge.agents.map((a) => ({ value: `forge:${a.name}`, label: a.name, hint: a.label && a.label !== a.name ? a.label : 'Agent Forge bot' })),
      { value: 'gh', label: 'My own gh login', hint: login === undefined ? 'acts as you' : `${login} · acts as you` },
    ];
    const canAdd = interactive && deps.which('agent-forge');
    if (options.length === 1 && !canAdd) {
      ui.note(`${options[0]!.label}${options[0]!.hint ? ` (${options[0]!.hint})` : ''} — the only identity there is`, `GitHub identity for the ${role}`);
      return parseIdentity(options[0]!.value);
    }
    const initialValue = options.find((o) => current && o.value === identityText(current))?.value ?? options.find((o) => !other || o.value !== identityText(other))?.value ?? options[0]?.value;
    const picked = await ui.select({
      message: `GitHub identity for the ${role}`,
      options: canAdd ? [...options, { value: addBot, label: 'Add a new Agent Forge bot…', hint: 'runs: agent-forge add' }] : options,
      initialValue,
    });
    if (picked !== addBot) return parseIdentity(picked);
    if (!deps.forgeAdd()) ui.warn('agent-forge add did not finish; nothing was added.');
    readForge(); // the new bot, if any, is in the list the next time around
  }
}
