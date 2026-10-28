import { homedir } from 'node:os';
import { harnessLabel } from '../../harnesses/names.ts';
import { localLabel } from '../../harnesses/local.ts';
import type { AgentOption, Failover, Identities, Role } from './build-config.ts';

/** `~` for the home folder, for what is shown to a person. */
export const tilde = (path: string) => (path.startsWith(`${homedir()}/`) ? `~${path.slice(homedir().length)}` : path);

/** What an agent option runs: the CLI, the model, where a local one is served and the config folder when it has one. */
export const optionLine = (o: AgentOption) => [harnessLabel[o.harness], `${o.model}${o.provider ? ` (${localLabel[o.provider]})` : ''}`, ...(o.configDir ? [tilde(o.configDir)] : [])].join(' · ');

const personaLine = ({ persona }: Role) => (persona ? [`${persona.name ?? '(no name)'}${persona.prompt ? ` · ${persona.prompt.length > 60 ? `${persona.prompt.slice(0, 59)}…` : persona.prompt}` : ''}`] : []);
const roleLine = (r: Role, options: Record<string, AgentOption>) => [`${r.identity.kind === 'gh' ? 'your gh login' : r.identity.agent} · ${r.option} · ${optionLine(options[r.option]!)}`, ...personaLine(r).map((p) => `\n          persona: ${p}`)].join('');

/** What is about to be written, in one box. */
export const summary = (repos: string[], author: Role, reviewer: Role, options: Record<string, AgentOption>, failover: Failover | undefined, out: string, identities: Identities = 'separate') =>
  [
    `Repos     ${repos.join(', ')}`,
    ...(identities === 'shared' ? ['Identity  shared: both roles act as your gh login'] : []),
    `Options   ${Object.keys(options).join(', ')}`,
    `Author    ${roleLine(author, options)}`,
    `Reviewer  ${roleLine(reviewer, options)}`,
    ...(failover?.enabled ? [`Failover  ${failover.order.join(' → ')}`] : []),
    `Saved to  ${tilde(out)}`,
  ].join('\n');
