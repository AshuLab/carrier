import { execFile } from 'node:child_process';
import { resolveBinary } from '../harnesses/common.ts';
import { listLocalModels, localKinds, type LocalProvider } from '../harnesses/local.ts';
import { harnessNames, type HarnessName } from '../harnesses/names.ts';
import type { Account } from '../config/providers.ts';
import { agyLogin, cliLoggedIn, startAgy } from './doctor.ts';

export type Login = 'in' | 'out' | 'unknown';

/** What the detector asks of the machine, replaceable for tests. */
export interface Machine {
  /** The real binary of that name on the PATH (never a wrapper); throws when there is none. */
  resolveBinary: (name: string) => string;
  /** The first line of `--version`; undefined when it cannot be read. */
  version: (command: string) => Promise<string | undefined>;
  /** The doctor's login check, with the account's config folder in the environment. 'unknown' when it cannot tell. */
  login: (harness: HarnessName, configDir: string | undefined, command: string) => Promise<Login>;
  /** The models a local server has; throws when it does not answer. */
  localModels: (local: LocalProvider) => Promise<string[]>;
}

export type Found = { found: false } | { found: true; path: string; version?: string };
export type Server = { running: false } | { running: true; models: string[] };
export type Detected = {
  harnesses: Record<HarnessName, Found>;
  /** The login of each account asked about; 'unknown' when its CLI was not found or could not tell. */
  accounts: Record<string, Login>;
  servers: Record<LocalProvider, Server>;
};

/** What the Mac has: per harness its binary and version, per account its login, and the local servers that answer. Creates nothing. */
export async function detect(machine: Machine, accounts: Record<string, Pick<Account, 'harness' | 'configDir' | 'command'>>): Promise<Detected> {
  const harnesses = Object.fromEntries(
    await Promise.all(
      harnessNames.map(async (harness): Promise<[HarnessName, Found]> => {
        try {
          const path = machine.resolveBinary(harness);
          const version = await machine.version(path);
          return [harness, { found: true, path, ...(version !== undefined && { version }) }];
        } catch {
          return [harness, { found: false }];
        }
      }),
    ),
  ) as Record<HarnessName, Found>;

  const login = async ({ harness, configDir, command }: Pick<Account, 'harness' | 'configDir' | 'command'>): Promise<Login> => {
    const found = harnesses[harness];
    const bin = command ?? (found.found ? found.path : undefined);
    return bin === undefined ? 'unknown' : machine.login(harness, configDir, bin).catch(() => 'unknown' as const);
  };
  const [signedIn, servers] = await Promise.all([
    Promise.all(Object.entries(accounts).map(async ([name, a]) => [name, await login(a)] as const)),
    Promise.all(localKinds.map(async (kind): Promise<[LocalProvider, Server]> => [kind, await machine.localModels(kind).then((models) => ({ running: true as const, models }), () => ({ running: false as const }))])),
  ]);
  return { harnesses, accounts: Object.fromEntries(signedIn), servers: Object.fromEntries(servers) as Record<LocalProvider, Server> };
}

export const realMachine: Machine = {
  resolveBinary: (name) => resolveBinary(name),
  version: (command) =>
    new Promise((resolve) =>
      execFile(command, ['--version'], { timeout: 5_000 }, (error, stdout) => resolve(error === null ? stdout.split('\n')[0]?.trim() || undefined : undefined)),
    ),
  login: async (harness, configDir, command) => {
    if (harness === 'agy') return agyLogin({ startAgy });
    return (await cliLoggedIn(harness, configDir, undefined, command)) ? 'in' : 'out';
  },
  localModels: (local) => listLocalModels(local),
};
