import type { ConfigError } from './load.ts';

/** A config problem with a known kind: the key path and the kind are the parameters ([ADR 0055](../../docs/adr/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)). */
export type ConfigProblem = { code: string; params: { path: string; problem: string } };

/**
 * The kind of a problem `loadConfig` reports, read from the words the schema gives it (`schema.ts`; `problems.test.ts` loads a real config for each),
 * or null for any other: a repo that is not `owner/name`, and a failover step of a role that repeats another, is the role's own, or names a provider that is not declared.
 */
export function configProblem({ path, message }: ConfigError): ConfigProblem | null {
  const repo = /^repos\.(\d+)\.name$/.exec(path);
  if (repo && message === 'must be owner/name') return { code: 'config.problem', params: { path: `repos[${repo[1]}]`, problem: 'notARepo' } };
  const step = /^(failover\.roles\.(?:author|reviewer|leadReviewer)\.\d+)(\.provider)?$/.exec(path);
  if (step === null) return null;
  const at = step[1]!;
  if (step[2] !== undefined && message.endsWith('" is not declared in providers')) return { code: 'config.problem', params: { path: at, problem: 'providerNotDeclared' } };
  if (message.endsWith(': step repeats another step of the list')) return { code: 'config.problem', params: { path: at, problem: 'stepRepeated' } };
  if (message.endsWith(": step is the role's own provider and model, so it would move nowhere")) return { code: 'config.problem', params: { path: at, problem: 'stepOwnRole' } };
  return null;
}
