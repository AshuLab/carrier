import { readProvidersFile, type Providers } from '../config/providers.ts';
import { detect, type Machine } from '../doctor/detect.ts';
import { harnessNames, type HarnessName } from '../harnesses/names.ts';
import { localKinds, type LocalProvider } from '../harnesses/local.ts';
import type { Clock } from '../orchestration/clock.ts';
import { PROBE_LIMIT_MS, type ToolState } from './health.ts';

export type ProvidersReply = {
  accounts: { name: string; harness: HarnessName; displayName?: string; command?: string; configDir?: string; enabled: boolean; found: boolean; path?: string; version?: string; state: ToolState }[];
  /** A harness whose CLI is found and no account has. */
  unadded: { harness: HarnessName; path: string; version?: string }[];
  servers: { kind: LocalProvider; running: boolean; models: string[] }[];
  /** `providers.json` does not match: its first bad key and why, with no accounts. */
  problem?: { path: string; message: string };
};

/** Resolves with `onTimeout()` when the probe has not answered by the limit; a probe that fails is the caller's to handle. */
function within<T>(clock: Clock, probe: Promise<T>, onTimeout: () => T): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const cancel = clock.after(PROBE_LIMIT_MS, async () => {
      try {
        resolve(onTimeout());
      } catch (error) {
        reject(error);
      }
    });
    probe.then(resolve, reject).finally(cancel);
  });
}

/**
 * What the Mac has, for the app's Providers page: the accounts of `providers.json` (read now) with their state, the harnesses found that no
 * account has, and the local servers. Built from the one detector; a probe that does not answer in five seconds is `unknown`, a version
 * that cannot be read is left out.
 */
export function createProviders({ clock, machine, binaryFound }: { clock: Clock; machine: Machine; binaryFound: (command: string) => boolean }) {
  const limited: Machine = {
    resolveBinary: machine.resolveBinary,
    version: (command) => within(clock, machine.version(command).then((read) => read?.trim() || undefined, () => undefined), () => undefined),
    login: (harness, configDir, command) => within(clock, machine.login(harness, configDir, command), () => 'unknown'),
    localModels: (local) =>
      within(clock, machine.localModels(local), () => {
        throw new Error('the server did not answer in time');
      }),
  };

  return async (): Promise<ProvidersReply> => {
    const read = readProvidersFile();
    if (read.ok === false) return { accounts: [], unadded: [], servers: [], problem: read.errors[0]! };
    const providers: Providers = read.providers;
    const detected = await detect(limited, providers);

    const accounts = await Promise.all(
      Object.entries(providers).map(async ([name, account]) => {
        const seen = detected.harnesses[account.harness];
        // an account with its own binary is judged by that one, not by the first on the PATH
        const found = account.command === undefined ? seen.found : binaryFound(account.command);
        const path = account.command ?? (seen.found ? seen.path : undefined);
        const version = account.command === undefined ? (seen.found ? seen.version : undefined) : found ? await limited.version(account.command) : undefined;
        const login = detected.accounts[name];
        const state: ToolState = found === false ? 'missing' : login === 'in' ? 'ready' : login === 'out' ? 'signedOut' : 'unknown';
        return {
          name,
          harness: account.harness,
          ...(account.displayName !== undefined && { displayName: account.displayName }),
          ...(account.command !== undefined && { command: account.command }),
          ...(account.configDir !== undefined && { configDir: account.configDir }),
          enabled: account.enabled !== false,
          found,
          ...(found && path !== undefined && { path }),
          ...(version !== undefined && { version }),
          state,
        };
      }),
    );
    const unadded = harnessNames.flatMap((harness) => {
      const seen = detected.harnesses[harness];
      return seen.found && accounts.every((account) => account.harness !== harness) ? [{ harness, path: seen.path, ...(seen.version !== undefined && { version: seen.version }) }] : [];
    });
    const servers = localKinds.map((kind) => {
      const server = detected.servers[kind];
      return { kind, running: server.running, models: server.running ? server.models : [] };
    });
    return { accounts, unadded, servers };
  };
}
