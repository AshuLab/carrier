import type { Flags } from '../cli/args.ts';
import { roleSlots, camel, roleFlagSuffixes, extraFlagSuffixes, type RoleSlot, type Camel } from './roles.ts';

type RoleFlagName = `${RoleSlot}${(typeof roleFlagSuffixes)[number]}`;
type ExtraFlagName = `extra-reviewer${'' | (typeof extraFlagSuffixes)[number]}`;

/** Flags answer questions ahead of time; whatever is missing is asked. `<role>` is one of the slots of `roleSlots` and its keys come from that table: `<role>` and `<role>Provider` are `<harness>:<model>` and `lmstudio` or `ollama` when that model runs there, `<role>Profile` is `forge:<agent>` or `gh`, `<role>Effort` one of the five levels, `<role>PersonaName` and `<role>PersonaPrompt` the persona, and `<role>Failover` the steps (`<account>[:<model>]`, in order). An extra reviewer is named by its flags: `extraReviewer` is every `"<name>=<harness>:<model>"` and each `extraReviewer<Field>` every `"<name>=<value>"` for that field, as `parseExtras` reads them. */
export type InitFlags = {
  repo?: string[];
  /** `forge:<agent>` or `gh`. */
  orchestratorProfile?: string;
  out?: string;
  yes?: boolean;
} & { [Key in Camel<RoleFlagName>]?: string } & { [Key in Camel<`${RoleSlot}-failover`>]?: string[] } & { [Key in Camel<ExtraFlagName>]?: string[] };

/** The flags of `init` out of the parsed command line, each role's from the table of slots. */
export function initFlagsOf(flags: Flags): InitFlags {
  const values = flags as Record<string, unknown>;
  const flat = ['repo', 'orchestrator-profile', 'out', 'yes', ...roleSlots.flatMap((slot) => [...roleFlagSuffixes.map((suffix) => `${slot}${suffix}`), `${slot}-failover`]), 'extra-reviewer', ...extraFlagSuffixes.map((suffix) => `extra-reviewer${suffix}`)];
  return Object.fromEntries(flat.map((name) => [camel(name), values[name]])) as InitFlags;
}
