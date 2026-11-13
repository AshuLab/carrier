import { createScopedLogger } from '@ashulab/universal-logger';
import { probes } from './probes.ts';
import { ProbeError, type QuotaSnapshot, type QuotaTarget, type UsagePorts } from './types.ts';

const log = createScopedLogger('usage');

export const QUOTA_KEPT_MS = 60_000;

/**
 * Live quotas, one probe per account at a time and kept for a minute unless a refresh is asked. Callers that arrive while a probe is
 * running share it. A probe the provider rate limits answers with the last good snapshot, marked stale, so the page keeps its numbers.
 */
export function createQuotas(ports: UsagePorts) {
  const kept = new Map<string, { at: number; snapshot: QuotaSnapshot }>();
  const lastGood = new Map<string, QuotaSnapshot>();
  const running = new Map<string, Promise<QuotaSnapshot>>();

  async function probe(key: string, target: QuotaTarget): Promise<QuotaSnapshot> {
    const { provider } = target;
    const checkedAt = ports.clock.now();
    let snapshot: QuotaSnapshot;
    try {
      snapshot = { status: 'ok', ...(await probes[provider](ports, target)), provider, checkedAt };
    } catch (error) {
      // Only a ProbeError's own words are kept: anything else may carry what a provider or a child printed.
      const known = error instanceof ProbeError;
      if (known === false) log.error('a quota probe failed unexpectedly', { provider, name: error instanceof Error ? error.name : typeof error });
      snapshot = { provider, status: known ? error.status : 'error', checkedAt, windows: [], message: known ? error.message : 'the check failed' };
    }
    if (snapshot.status === 'ok') lastGood.set(key, snapshot);
    else if (snapshot.status === 'rate_limited') {
      const before = lastGood.get(key);
      if (before !== undefined) snapshot = { ...before, status: 'rate_limited', stale: true, ...(snapshot.message !== undefined && { message: snapshot.message }) };
    }
    if (snapshot.status !== 'ok') log.warn('a quota probe did not succeed', { provider, status: snapshot.status });
    kept.set(key, { at: ports.clock.now(), snapshot });
    return snapshot;
  }

  return (target: QuotaTarget, { refresh = false }: { refresh?: boolean } = {}): Promise<QuotaSnapshot> => {
    const key = `${target.provider}:${target.configDir ?? ''}:${target.command ?? ''}`;
    const hit = kept.get(key);
    if (refresh === false && hit !== undefined && ports.clock.now() - hit.at < QUOTA_KEPT_MS) return Promise.resolve(hit.snapshot);
    let flight = running.get(key);
    if (flight === undefined) {
      flight = probe(key, target).finally(() => running.delete(key));
      running.set(key, flight);
    }
    return flight;
  };
}
