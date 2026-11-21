/** Carrier's permission scale ([ADR 0033](../../docs/adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md), widened by [ADR 0036](../../docs/adr/0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md)): what a session may do without asking the person, on which the options of each harness sit. */
export type Level = 0 | 1 | 2 | 3;
export type ScaleHarness = 'claude' | 'codex';

/** The broadest options of each harness at each level, which a child is given; a harness with no option at the top levels (Codex at 3) has none, and a child steps down to its last. */
const scale: Record<ScaleHarness, Record<string, string>[]> = {
  claude: [{ permissionMode: 'dontAsk' }, { permissionMode: 'default' }, { permissionMode: 'acceptEdits' }, { permissionMode: 'auto' }],
  codex: [
    { sandbox: 'read-only', approvalPolicy: 'untrusted' },
    { sandbox: 'workspace-write', approvalPolicy: 'untrusted' },
    { sandbox: 'workspace-write', approvalPolicy: 'on-request' },
  ],
};
/** What a harness does with none of them set: the adapters' defaults. */
const defaults: Record<ScaleHarness, Record<string, string>> = { claude: { permissionMode: 'default' }, codex: { sandbox: 'workspace-write', approvalPolicy: 'untrusted' } };

export const isScaleHarness = (harness: string): harness is ScaleHarness => harness === 'claude' || harness === 'codex';

/** The options that fix a level, as these have them: the defaults of the adapter for the ones not set. */
export const scaleOptions = (harness: ScaleHarness, options: Record<string, string>): Record<string, string> =>
  Object.fromEntries(Object.entries({ ...defaults[harness], ...options }).filter(([id]) => id in defaults[harness]));

/** The level of the options of a harness, none set meaning the adapter's defaults; undefined when they are off the scale. */
export function levelOf(harness: ScaleHarness, options: Record<string, string>): Level | undefined {
  const own = scaleOptions(harness, options);
  // the options that sit at a level beside the one a child is given: `plan` reads like `dontAsk`, a Codex sandbox that reads is 0 with any policy, and `never` edits like `on-request`
  if (own.permissionMode === 'plan' || own.sandbox === 'read-only') return 0;
  const same = own.approvalPolicy === 'never' ? { ...own, approvalPolicy: 'on-request' } : own;
  const level = scale[harness].findIndex((step) => Object.entries(step).every(([id, value]) => same[id] === value));
  return level < 0 ? undefined : (level as Level);
}

/** Whether an agent says anything about permission: any of the options that fix a level. The model and the effort say nothing of it. */
const setsPermission = (harness: ScaleHarness, agentOptions: Record<string, string>) => Object.keys(defaults[harness]).some((id) => id in agentOptions);

/**
 * The options a child of a session at `parentLevel` gets.
 * An agent that sets a permission option of its own is capped by it: it gets the lower of its level and the parent's, never a higher one.
 * An agent that sets none has no level of its own to cap it, and the adapter's default is not a choice: it takes the parent's level (Codex has nothing above 2).
 * An agent whose options are off the scale is not honoured: it gets the broadest option of its harness at or under the parent's level, and counts as lowered.
 */
export function childOptions(harness: ScaleHarness, agentOptions: Record<string, string>, parentLevel: Level): { options: Record<string, string>; level: Level; lowered: boolean } {
  const top = Math.min(parentLevel, scale[harness].length - 1) as Level;
  if (setsPermission(harness, agentOptions) === false) return { options: { ...agentOptions, ...scale[harness][top] }, level: top, lowered: false };
  const own = levelOf(harness, agentOptions);
  if (own !== undefined && own <= parentLevel) return { options: { ...agentOptions, ...scaleOptions(harness, agentOptions) }, level: own, lowered: false };
  return { options: { ...agentOptions, ...scale[harness][top] }, level: top, lowered: true };
}

/** The first Codex app-server whose approval of an MCP tool the adapter can answer. */
export const CODEX_DELEGATION_FLOOR = '0.122.0';

const olderThan = (found: string, floor: string) => {
  const [a, b] = [found, floor].map((version) => version.split('.').map(Number));
  const at = a!.findIndex((part, index) => part !== b![index]);
  return at >= 0 && a![at]! < b![at]!;
};

/** Why a session with these options may not delegate, in words for the agent, or undefined when it may: it needs options on the scale, whatever the mode, and a Codex app-server of the floor or later. */
export function delegationRefusal(harness: string, options: Record<string, string>, appServerVersion?: string): string | undefined {
  if (!isScaleHarness(harness)) return `A ${harness} session cannot delegate`;
  const own = scaleOptions(harness, options);
  if (levelOf(harness, options) === undefined) return `This session's options (${Object.entries(own).map(([key, value]) => `${key} ${value}`).join(', ')}) are off the permission scale, so a child cannot be given a level`;
  if (harness === 'codex' && appServerVersion === undefined) return 'The version of this Codex app-server is not known, so delegation is not offered';
  if (harness === 'codex' && olderThan(appServerVersion!, CODEX_DELEGATION_FLOOR)) return `This Codex app-server is ${appServerVersion}, older than ${CODEX_DELEGATION_FLOOR}, which delegation needs`;
  return undefined;
}
