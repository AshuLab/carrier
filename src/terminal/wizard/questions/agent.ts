import { localKinds, localLabel, type LocalProvider } from '../../../harnesses/local.ts';
import { harnessLabel, harnessNames, localProvidersOf, nativeProvider, type HarnessName } from '../../../harnesses/names.ts';
import type { Option, Ui } from '../../prompts/types.ts';
import { parseHarnessModel, parseProvider, type Role } from '../build-config.ts';
import type { InitDeps } from '../deps.ts';
import type { Answered } from '../prior.ts';

// Aliases the Claude CLI resolves to the latest model of each family, so they do not go stale like a model id does.
const claudeModels: Option<string>[] = [
  { value: 'sonnet', label: 'sonnet', hint: 'latest Sonnet' },
  { value: 'opus', label: 'opus', hint: 'latest Opus' },
  { value: 'fable', label: 'fable', hint: 'latest Fable' },
];
const otherModel = '\0other';


const native = '\0native';

// Three questions, each with one meaning: the harness (the CLI that runs the loop and the tools), the provider that
// serves the model (the harness's own cloud, or a local server) and the model. The provider question only appears
// when there is a choice, so the common path stays at two.
export async function askAgent(ui: Ui, role: 'author' | 'reviewer', given: { flag?: string; provider?: string }, installed: readonly HarnessName[], locals: Partial<Record<LocalProvider, string[]>>, deps: InitDeps, preferred: HarnessName, current?: Answered): Promise<Pick<Role, 'harness' | 'model' | 'provider'>> {
  if (given.flag) return { ...parseHarnessModel(given.flag), ...(given.provider && { provider: parseProvider(given.provider) }) };
  if (installed.length === 0) throw new Error(`None of ${harnessNames.join(', ')} is installed; install one and run this again.`);
  const harness: HarnessName = installed.length === 1 ? installed[0]! : await ui.select<HarnessName>({ message: `Which agent CLI runs the ${role}?`, options: installed.map((p) => ({ value: p, label: harnessLabel[p] })), initialValue: [current?.harness, preferred].find((h): h is HarnessName => h !== undefined && installed.includes(h)) ?? installed[0]! });

  let provider: LocalProvider | undefined;
  const servers = localKinds.filter((kind) => localProvidersOf[harness].includes(kind)); // Antigravity has none
  if (servers.some((kind) => locals[kind])) {
    const choice = await ui.select({
      message: `Which provider serves the ${role}'s model?`,
      options: [
        { value: native, label: nativeProvider[harness], hint: 'cloud' },
        ...servers.map((kind) => ({ value: kind as string, label: `${localLabel[kind]} (local)`, hint: locals[kind] ? `${locals[kind].length} models, runs on this machine` : 'not running: start its server to use it', disabled: !locals[kind] })),
      ],
      initialValue: current?.harness === harness && current.provider && locals[current.provider] ? current.provider : native,
    });
    if (choice !== native) provider = parseProvider(choice);
  }

  const typed = async (suggestion?: string) => (await ui.text({ message: `Model for the ${role}`, placeholder: suggestion ?? 'model name', defaultValue: suggestion, validate: (v) => (v.trim() ? undefined : 'Required') })).trim();
  const known: Option<string>[] = provider ? locals[provider]!.map((value) => ({ value, label: value })) : harness === 'claude' ? claudeModels : harness === 'codex' ? deps.codexModels() : deps.agyModels();
  const configured = !provider && harness === 'codex' ? deps.codexModel() : undefined; // what the user already runs Codex with
  if (known.length === 0) return { harness, model: await typed(configured), ...(provider && { provider }) };
  const same = current?.harness === harness && current.provider === provider ? current.model : undefined; // the model it has now, when the harness and provider did not change
  const options = same !== undefined && !known.some((k) => k.value === same) ? [{ value: same, label: same, hint: 'current' }, ...known] : known;
  const initial = [same, configured, 'sonnet'].find((m) => m !== undefined && options.some((k) => k.value === m)) ?? options[0]!.value;
  const choice = await ui.select({ message: `Model for the ${role}`, options: [...options, { value: otherModel, label: 'Other…', hint: 'type a model id' }], initialValue: initial });
  return { harness, model: choice === otherModel ? await typed() : choice, ...(provider && { provider }) };
}
