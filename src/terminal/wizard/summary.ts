import { homedir } from 'node:os';
import { harnessLabel } from '../../harnesses/names.ts';
import { localLabel } from '../../harnesses/local.ts';
import type { Identities } from './build-config.ts';
import type { Answered } from './prior.ts';

/** `~` for the home folder, for what is shown to a person. */
export const tilde = (path: string) => (path.startsWith(`${homedir()}/`) ? `~${path.slice(homedir().length)}` : path);


const personaLine = ({ persona }: Answered) => (persona ? [`${persona.name ?? '(no name)'}${persona.prompt ? ` · ${persona.prompt.length > 60 ? `${persona.prompt.slice(0, 59)}…` : persona.prompt}` : ''}`] : []);
const roleLine = (r: Answered) => [`${r.identity.kind === 'gh' ? 'your gh login' : r.identity.agent} · ${harnessLabel[r.harness]} · ${r.model}${r.provider ? ` (${localLabel[r.provider]})` : ''}`, ...personaLine(r).map((p) => `\n          persona: ${p}`)].join('');

/** What is about to be written, in one box. */
export const summary = (repos: string[], author: Answered, reviewer: Answered, out: string, identities: Identities = 'separate') =>
  [`Repos     ${repos.join(', ')}`, ...(identities === 'shared' ? ['Identity  shared: both roles act as your gh login'] : []), `Author    ${roleLine(author)}`, `Reviewer  ${roleLine(reviewer)}`, `Saved to  ${tilde(out)}`].join('\n');
