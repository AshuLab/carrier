import { homedir } from 'node:os';
import type { Detected } from '../../doctor/detect.ts';
import { harnessLabel, harnessNames, type HarnessName } from '../../harnesses/names.ts';
import { localKinds, localLabel, type LocalProvider } from '../../harnesses/local.ts';
import type { AIProvider, Failover, Identities, Role } from './build-config.ts';

/** `~` for the home folder, for what is shown to a person. */
export const tilde = (path: string) => (path.startsWith(`${homedir()}/`) ? `~${path.slice(homedir().length)}` : path);

/** What an AI provider runs: the CLI, where a local one is served and the config folder when it has one. */
export const providerLine = (p: AIProvider) => [harnessLabel[p.harness], ...(p.provider ? [`${localLabel[p.provider]} (local)`] : []), ...(p.configDir ? [tilde(p.configDir)] : [])].join(' · ');

const personaLine = ({ persona }: Role) => (persona ? [`${persona.name ?? '(no name)'}${persona.prompt ? ` · ${persona.prompt.length > 60 ? `${persona.prompt.slice(0, 59)}…` : persona.prompt}` : ''}`] : []);
const roleLine = (r: Role, providers: Record<string, AIProvider>) => {
  const p = providers[r.provider];
  const pDesc = p ? `${r.provider} (${providerLine(p)})` : r.provider;
  return [`${r.identity.kind === 'gh' ? 'your gh login' : r.identity.agent} · ${pDesc} · ${r.model}`, ...personaLine(r).map((item) => `\n          persona: ${item}`)].join('');
};

const loginText = { in: 'signed in', out: 'signed out', unknown: 'login not checked' } as const;

/** What the detector found, one line per tool: where the binary is and its version, whether it is signed in, which servers answer. */
export const foundLines = ({ harnesses, accounts, servers }: Detected) => [
  ...harnessNames.map((harness) => {
    const found = harnesses[harness];
    if (!found.found) return `${harnessLabel[harness].padEnd(12)} not found`;
    return `${harnessLabel[harness].padEnd(12)} ${[tilde(found.path), found.version, accounts[harness] === undefined ? undefined : loginText[accounts[harness]]].filter((part) => part !== undefined).join(' · ')}`;
  }),
  ...localKinds.map((kind) => `${localLabel[kind].padEnd(12)} ${servers[kind].running ? `running · ${servers[kind].models.length} models` : 'not running'}`),
];

/** What is about to be written, in one box. */
export const summary = (
  repos: string[],
  author: Role,
  reviewer: Role,
  providers: Record<string, AIProvider>,
  failover: Failover | undefined,
  out: string,
  providersPath: string,
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
    ...(failover?.roles
      ? [`Failover    ${Object.entries(failover.roles).filter(([_, steps]) => steps.length > 0).map(([role, steps]) => `${role}: ${steps.map((step) => (step.model ? `${step.provider} ${step.model}` : step.provider)).join(' → ')}`).join(' · ')}`]
      : []),
    `Saved to    ${tilde(out)}`,
    `Accounts in ${tilde(providersPath)} (the Carrier folder, wherever the config goes)`,
  ].join('\n');
