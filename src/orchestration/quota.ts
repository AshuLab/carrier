import type { QuotaSnapshot, QuotaTarget } from '../usage/types.ts';

/** The quota of one account, read from the provider now (not from a cache); the snapshot's status says when the probe failed or was rate limited. */
export type QuotaReader = (target: QuotaTarget) => Promise<QuotaSnapshot>;
