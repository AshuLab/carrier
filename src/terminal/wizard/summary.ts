import { homedir } from 'node:os';
import { harnessLabel, type HarnessName } from '../../harnesses/names.ts';
import { localLabel, type LocalProvider } from '../../harnesses/local.ts';
import type { AIProvider, Failover, Identities, Role } from './build-config.ts';

/** `~` for the home folder, for what is shown to a person. */
export const tilde = (path: string) => (path.startsWith(`${homedir()}/`) ? `~${path.slice(homedir().length)}` : path);

/** What an AI provider runs: the CLI, where a local one is served and the config folder when it has one. */
export const providerLine = (p: AIProvider) => [harnessLabel[p.harness], ...(p.provider ? [`${localLabel[p.provider]} (local)`] : []), ...(p.configDir ? [tilde(p.configDir)] : [])].join(' · ');

/** What an agent option runs: the CLI, the model, where a local one is served and the config folder when it has one. */
export const optionLine = (o: { harness: HarnessName; model: string; provider?: string; configDir?: string }) => [harnessLabel[o.harness], `${o.model}${o.provider ? ` (${localLabel[o.provider as LocalProvider]})` : ''}`, ...(o.configDir ? [tilde(o.configDir)] : [])].join(' · ');

const personaLine = ({ persona }: Role) => (persona ? [`${persona.name ?? '(no name)'}${persona.prompt ? ` · ${persona.prompt.length > 60 ? `${persona.prompt.slice(0, 59)}…` : persona.prompt}` : ''}`] : []);
const roleLine = (r: Role, providers: Record<string, AIProvider>) => {
  const p = providers[r.provider];
  const pDesc = p ? `${r.provider} (${providerLine(p)})` : r.provider;
  return [`${r.identity.kind === 'gh' ? 'your gh login' : r.identity.agent} · ${pDesc} · ${r.model}`, ...personaLine(r).map((item) => `\n          persona: ${item}`)].join('');
};

/** What is about to be written, in one box. */
export const summary = (
  repos: string[],
  author: Role,
  reviewer: Role,
  providers: Record<string, AIProvider>,
  failover: Failover | undefined,
  out: string,
  identities: Identities = 'separate',
  leadReviewer?: Role,
) =>
  [
    `Repos       ${repos.join(', ')}`,
    ...(identities === 'shared' ? ['Identity    shared: both roles act as your gh login'] : []),
    `Providers   ${Object.keys(providers).join(', ')}`,
    `Author      ${roleLine(author, providers)}`,
    `Reviewer    ${roleLine(reviewer, providers)}`,
    ...(leadReviewer ? [`Lead Rev    ${roleLine(leadReviewer, providers)}`] : []),
    ...(failover?.enabled
      ? [
          `Failover    ${[
            ...(failover.default?.length ? [failover.roles ? `default: ${failover.default.join(' → ')}` : failover.default.join(' → ')] : []),
            ...(failover.roles ? Object.entries(failover.roles).filter(([_, list]) => list && list.length > 0).map(([role, list]) => `${role}: ${list!.join(' → ')}`) : []),
          ].join(' · ')}`,
        ]
      : []),
    `Saved to    ${tilde(out)}`,
  ].join('\n');
