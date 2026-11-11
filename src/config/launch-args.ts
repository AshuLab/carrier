import type { HarnessName } from '../harnesses/names.ts';

// The flags Carrier sets itself: repeating one would change the permission mode or break the parsing of events (spec providers-in-settings).
const refusedFlags: Record<HarnessName, readonly string[]> = {
  claude: ['-p', '--model', '--permission-mode', '--output-format', '--resume', '--name', '--add-dir', '--settings', '--autocompact'],
  codex: ['--model', '--json', '--dangerously-bypass-approvals-and-sandbox', '--sandbox'],
  agy: [],
};
const refusedCodexKeys = ['model_provider', 'carrier_marker', 'model_auto_compact_token_limit'];

/** The flag of a token: `--model=x` is `--model`. */
const flagOf = (token: string) => (token.startsWith('-') ? token.split('=')[0]! : undefined);

/** The key of a `-c`/`--config` pair in each form the CLI takes: `-c k=v`, `-ck=v`, `--config k=v`, `--config=k=v`. */
function configKeyAt(args: readonly string[], i: number): string | undefined {
  const token = args[i]!;
  const pair = token === '-c' || token === '--config' ? args[i + 1] : token.startsWith('--config=') ? token.slice('--config='.length) : /^-c[^-]/.test(token) ? token.slice(2) : undefined;
  return pair?.split('=')[0]?.trim();
}

/** What an entry of `launchArgs` repeats of what Carrier sets: the flag, or the config key; undefined when none does. Never the value of an argument. */
export function refusedLaunchArg(harness: HarnessName, args: readonly string[]): { index: number; what: string } | undefined {
  for (const [index, token] of args.entries()) {
    const flag = flagOf(token);
    if (flag !== undefined && refusedFlags[harness].includes(flag)) return { index, what: flag };
    const key = harness === 'codex' ? configKeyAt(args, index) : undefined;
    if (key !== undefined && refusedCodexKeys.includes(key)) return { index, what: `the config key ${key}` };
  }
  return undefined;
}
