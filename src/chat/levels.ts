/** Carrier's permission scale ([ADR 0033](../../docs/adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md)): what a session may do without asking the person, on which the options of each harness sit. */
export type Level = 0 | 1 | 2;
export type ScaleHarness = 'claude' | 'codex';

/** The options of each harness that fix a level, by level; Codex's level 0 is `read-only` whatever the policy. */
const scale: Record<ScaleHarness, Record<string, string>[]> = {
  claude: [{ permissionMode: 'dontAsk' }, { permissionMode: 'default' }, { permissionMode: 'acceptEdits' }],
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
  if (harness === 'codex' && own.sandbox === 'read-only') return 0;
  const level = scale[harness].findIndex((step) => Object.entries(step).every(([id, value]) => own[id] === value));
  return level < 0 ? undefined : (level as Level);
}

/**
 * The options a child of a session at `parentLevel` gets: those of its own agent at the lower of its level and the parent's, never a higher one.
 * An agent whose options are off the scale is not honoured: it gets the parent's level, as the broadest option at or under it, and counts as lowered. One that sets none is taken at the adapter's defaults.
 */
export function childOptions(harness: ScaleHarness, agentOptions: Record<string, string>, parentLevel: Level): { options: Record<string, string>; level: Level; lowered: boolean } {
  const own = levelOf(harness, agentOptions);
  if (own !== undefined && own <= parentLevel) return { options: { ...agentOptions, ...scaleOptions(harness, agentOptions) }, level: own, lowered: false };
  return { options: { ...agentOptions, ...scale[harness][parentLevel] }, level: parentLevel, lowered: true };
}

/** The option and the values of it that ask the person before a change: the only modes a session may delegate from. */
const asking: Record<ScaleHarness, { id: string; values: string[] }> = {
  claude: { id: 'permissionMode', values: ['default', 'acceptEdits'] },
  codex: { id: 'approvalPolicy', values: ['untrusted', 'on-request'] },
};
/** The first Codex app-server whose approval of an MCP tool the adapter can answer. */
export const CODEX_DELEGATION_FLOOR = '0.122.0';

const olderThan = (found: string, floor: string) => {
  const [a, b] = [found, floor].map((version) => version.split('.').map(Number));
  const at = a!.findIndex((part, index) => part !== b![index]);
  return at >= 0 && a![at]! < b![at]!;
};

/** Why a session with these options may not delegate, in words for the agent, or undefined when it may: it needs a mode that asks the person, on the scale, and a Codex app-server of the floor or later. */
export function delegationRefusal(harness: string, options: Record<string, string>, appServerVersion?: string): string | undefined {
  if (!isScaleHarness(harness)) return `A ${harness} session cannot delegate`;
  const own = scaleOptions(harness, options);
  const { id, values } = asking[harness];
  if (!values.includes(own[id]!)) return `This session's ${id} is ${own[id]}, which does not ask the person before a change, so it cannot delegate; delegation needs ${values.join(' or ')}`;
  if (levelOf(harness, options) === undefined) return `This session's options (${Object.entries(own).map(([key, value]) => `${key} ${value}`).join(', ')}) are off the permission scale, so a child cannot be given a level`;
  if (harness === 'codex' && appServerVersion === undefined) return 'The version of this Codex app-server is not known, so delegation is not offered';
  if (harness === 'codex' && olderThan(appServerVersion!, CODEX_DELEGATION_FLOOR)) return `This Codex app-server is ${appServerVersion}, older than ${CODEX_DELEGATION_FLOOR}, which delegation needs`;
  return undefined;
}
