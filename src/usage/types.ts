import type { Clock } from '../orchestration/clock.ts';
import type { LocalProvider } from '../harnesses/local.ts';

export type QuotaProvider = 'claude' | 'codex' | 'agy' | 'local';
export type QuotaStatus = 'ok' | 'signed_out' | 'missing' | 'unavailable' | 'rate_limited' | 'error';

/** One rolling window, as a percentage used (clamped to 0..100) and when it resets: a time, or the provider's own words when it gives no time. */
export interface QuotaWindow {
  id: string;
  label: string;
  /** The pool or limit the window belongs to (an Antigravity group, a Codex limit id), when the provider has several. */
  group?: string;
  usedPercent: number;
  /** Epoch milliseconds. */
  resetsAt?: number;
  resetLabel?: string;
}

/** Claude's overage spend, in dollars: the provider reports minor units and they are scaled by its decimal places. */
export interface ExtraUsage {
  isEnabled: boolean;
  monthlyLimitUsd?: number;
  usedCreditsUsd?: number;
  utilization?: number;
  currency?: string;
}

export interface QuotaSnapshot {
  provider: QuotaProvider;
  status: QuotaStatus;
  /** Epoch milliseconds of the probe that produced the data; a stale snapshot keeps the time of the data it holds. */
  checkedAt: number;
  /** The windows are the last known ones: a later probe was rate limited. */
  stale?: true;
  windows: QuotaWindow[];
  planType?: string;
  /** Why the status is not `ok`; never holds a token or the output of a child process. */
  message?: string;
  extraUsage?: ExtraUsage;
  credits?: { hasCredits: boolean; unlimited: boolean; balance: string | null };
  rateLimitResetCredits?: unknown;
  aiCreditsNotice?: string;
  servers?: { kind: LocalProvider; running: boolean; models: string[] }[];
}

/** What a probe throws when it knows the status; anything else becomes `error` with no detail. */
export class ProbeError extends Error {
  status: Exclude<QuotaStatus, 'ok'>;
  constructor(status: Exclude<QuotaStatus, 'ok'>, message: string) {
    super(message);
    this.status = status;
  }
}

export interface RpcChild {
  send(line: string): void;
  onLine(fn: (line: string) => void): void;
  /** The child ended or could not start (`error.code === 'ENOENT'`: there is no such binary). */
  onExit(fn: (error?: NodeJS.ErrnoException) => void): void;
  kill(): void;
}

/** Everything the probes touch on the machine; the unit tests replace all of it. */
export interface UsagePorts {
  clock: Clock;
  /** Rejects when the server cannot be reached. */
  http(request: { url: string; method?: 'GET' | 'POST'; headers?: Record<string, string>; body?: string; timeoutMs: number }): Promise<{ status: number; json: unknown }>;
  /** Runs a command to its end with stdin closed. Rejects with `code` `ENOENT` (no such binary) or `ETIMEDOUT`. */
  run(command: string, args: string[], options: { env: NodeJS.ProcessEnv; timeoutMs: number }): Promise<{ code: number; stdout: string }>;
  spawnRpc(command: string, args: string[], env: NodeJS.ProcessEnv): RpcChild;
  files: { read(path: string): Promise<string> };
  /** The text of a generic-password item of the macOS login Keychain, read and never written. `undefined` when there is no such item or this is not a Mac; rejects when the Keychain did not answer (denied, locked, timed out). */
  keychain(service: string, account: string): Promise<string | undefined>;
  /** The models a local server has; rejects when it does not answer. */
  localModels(kind: LocalProvider): Promise<string[]>;
}

/** Which account to ask: the provider and, for Claude and Codex, the account's config folder and binary. */
export interface QuotaTarget {
  provider: QuotaProvider;
  configDir?: string;
  command?: string;
}
