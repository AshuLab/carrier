import { isAbsolute } from 'node:path';
import { localKinds, localLabel, type LocalProvider } from '../../../harnesses/local.ts';
import { harnessLabel, localProvidersOf, nativeProvider, type HarnessName } from '../../../harnesses/names.ts';
import type { Option, Ui } from '../../prompts/types.ts';
import type { AgentOption } from '../build-config.ts';
import type { InitDeps } from '../deps.ts';
import { tilde } from '../summary.ts';

// Aliases the Claude CLI resolves to the latest model of each family, so they do not go stale like a model id does.
const claudeModels: Option<string>[] = [
  { value: 'sonnet', label: 'sonnet', hint: 'latest Sonnet' },
  { value: 'opus', label: 'opus', hint: 'latest Opus' },
  { value: 'fable', label: 'fable', hint: 'latest Fable' },
];
const otherModel = '\0other';
const native = '\0native';
const inherit = '\0inherit';
const typedPath = '\0path';

/** The config folder of a Claude or Codex option: one it found, the environment, or a path. It holds the login, so each is shown with its state. Undefined inherits the environment. */
export async function askConfigDir(ui: Ui, harness: 'claude' | 'codex', deps: InitDeps, noun = 'option'): Promise<string | undefined> {
  const state = (dir?: string) => deps.loggedIn(harness, dir).then((ok) => (ok ? 'logged in' : 'not logged in'), () => 'could not check the login');
  const found = await Promise.all(deps.configFolders(harness).map(async (dir) => ({ value: dir, label: tilde(dir), hint: await state(dir) })));
  const choice = await ui.select({
    message: `Config folder of this ${harnessLabel[harness]} ${noun}`,
    options: [...found, { value: inherit, label: 'Inherit the environment', hint: `the login Carrier runs in: ${await state()}` }, { value: typedPath, label: 'Type a path…' }],
    initialValue: inherit,
  });
  if (choice === inherit) return undefined;
  if (choice !== typedPath) return tilde(choice);
  const typed = await ui.text({ message: `Config folder of this ${harnessLabel[harness]} ${noun} (absolute, or starting with ~/)`, validate: (v) => (isAbsolute(v.trim()) || v.trim().startsWith('~/') ? undefined : 'An absolute path, or one starting with ~/') });
  return typed.trim();
}

/** Ask the model for a role (author or reviewer) on a specific harness. */
export async function askModel(
  ui: Ui,
  harness: HarnessName,
  provider: LocalProvider | undefined,
  locals: Partial<Record<LocalProvider, string[]>>,
  deps: InitDeps,
  role: 'author' | 'reviewer' | 'lead reviewer',
  current?: string,
): Promise<string> {
  const typed = async (suggestion?: string) => (await ui.text({ message: `Model for the ${role}`, placeholder: suggestion ?? 'model name', defaultValue: suggestion, validate: (v) => (v.trim() ? undefined : 'Required') })).trim();
  const known: Option<string>[] = provider ? (locals[provider] ?? []).map((value) => ({ value, label: value })) : harness === 'claude' ? claudeModels : harness === 'codex' ? deps.codexModels() : deps.agyModels();
  const configured = !provider && harness === 'codex' ? deps.codexModel() : undefined;
  if (known.length === 0) return typed(current ?? configured);
  const initial = [current, configured, 'sonnet'].find((m) => m !== undefined && known.some((k) => k.value === m)) ?? known[0]!.value;
  const choice = await ui.select({ message: `Model for the ${role}`, options: [...known, { value: otherModel, label: 'Other…', hint: 'type a model id' }], initialValue: initial });
  return choice === otherModel ? await typed() : choice;
}

/** Creates a pure AI provider (harness, configDir, local provider) without a model. */
export async function askAIProvider(
  ui: Ui,
  installed: readonly HarnessName[],
  used: readonly HarnessName[],
  locals: Partial<Record<LocalProvider, string[]>>,
  deps: InitDeps,
): Promise<{ harness: HarnessName; provider?: LocalProvider; configDir?: string }> {
  const harness: HarnessName = installed.length === 1 ? installed[0]! : await ui.select<HarnessName>({ message: 'Which agent CLI runs this provider?', options: installed.map((p) => ({ value: p, label: harnessLabel[p] })), initialValue: installed.find((h) => !used.includes(h)) ?? installed[0]! });

  let provider: LocalProvider | undefined;
  const servers = localKinds.filter((kind) => localProvidersOf[harness].includes(kind));
  if (servers.some((kind) => locals[kind])) {
    const choice = await ui.select({
      message: 'Where does this provider run?',
      options: [
        { value: native, label: nativeProvider[harness], hint: 'cloud' },
        ...servers.map((kind) => ({ value: kind as string, label: `${localLabel[kind]} (local)`, hint: locals[kind] ? `${locals[kind].length} models, runs on this machine` : 'not running: start its server to use it', disabled: !locals[kind] })),
      ],
      initialValue: native,
    });
    if (choice !== native) provider = servers.find((kind) => kind === choice);
  }

  const configDir = harness === 'agy' ? undefined : await askConfigDir(ui, harness, deps, 'provider');
  return { harness, ...(provider && { provider }), ...(configDir && { configDir }) };
}

// What one option is, each question with one meaning: the harness (the CLI that runs the loop and the tools), the provider
// that serves the model (the harness's own cloud, or a local server), the model and, for Claude and Codex, the config folder
// that holds the login. The provider question only appears when there is a choice.
export async function askAgentOption(ui: Ui, installed: readonly HarnessName[], used: readonly HarnessName[], locals: Partial<Record<LocalProvider, string[]>>, deps: InitDeps): Promise<AgentOption> {
  const harness: HarnessName = installed.length === 1 ? installed[0]! : await ui.select<HarnessName>({ message: 'Which agent CLI runs this option?', options: installed.map((p) => ({ value: p, label: harnessLabel[p] })), initialValue: installed.find((h) => !used.includes(h)) ?? installed[0]! }); // another CLI than the options so far, when there is one

  let provider: LocalProvider | undefined;
  const servers = localKinds.filter((kind) => localProvidersOf[harness].includes(kind)); // Antigravity has none
  if (servers.some((kind) => locals[kind])) {
    const choice = await ui.select({
      message: 'Which provider serves the model of this option?',
      options: [
        { value: native, label: nativeProvider[harness], hint: 'cloud' },
        ...servers.map((kind) => ({ value: kind as string, label: `${localLabel[kind]} (local)`, hint: locals[kind] ? `${locals[kind].length} models, runs on this machine` : 'not running: start its server to use it', disabled: !locals[kind] })),
      ],
      initialValue: native,
    });
    if (choice !== native) provider = servers.find((kind) => kind === choice);
  }

  const typed = async (suggestion?: string) => (await ui.text({ message: 'Model of this option', placeholder: suggestion ?? 'model name', defaultValue: suggestion, validate: (v) => (v.trim() ? undefined : 'Required') })).trim();
  const known: Option<string>[] = provider ? locals[provider]!.map((value) => ({ value, label: value })) : harness === 'claude' ? claudeModels : harness === 'codex' ? deps.codexModels() : deps.agyModels();
  const configured = !provider && harness === 'codex' ? deps.codexModel() : undefined; // what the user already runs Codex with
  let model: string;
  if (known.length === 0) model = await typed(configured);
  else {
    const initial = [configured, 'sonnet'].find((m) => m !== undefined && known.some((k) => k.value === m)) ?? known[0]!.value;
    const choice = await ui.select({ message: 'Model of this option', options: [...known, { value: otherModel, label: 'Other…', hint: 'type a model id' }], initialValue: initial });
    model = choice === otherModel ? await typed() : choice;
  }

  const configDir = harness === 'agy' ? undefined : await askConfigDir(ui, harness, deps); // Antigravity has no setting for it
  return { harness, model, ...(provider && { provider }), ...(configDir && { configDir }) };
}
