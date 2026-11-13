import { homedir } from 'node:os';
import { join } from 'node:path';
import type { ChatAgent } from '../chat/config.ts';
import type { ChatDb } from '../chat/db.ts';
import { ChatRefused } from '../chat/runner.ts';
import { providersProblem, readProvidersFile, type Providers } from '../config/providers.ts';
import { enginePlacesOf } from '../config/engine-places.ts';
import { createHistory, type HistoryFilter, type HistoryPorts, type HistoryRoots } from './history.ts';
import { catalog, createPriceOverrides, PriceOverrideInvalid, type OverrideRequest } from './pricing.ts';
import { createQuotas } from './quotas.ts';
import type { QuotaSnapshot, QuotaTarget, UsagePorts } from './types.ts';

export type UsageArgs = { refresh?: boolean; days?: HistoryFilter['days']; provider?: HistoryFilter['provider']; source?: HistoryFilter['source']; search?: string; account?: string };

/** The wire form of an override: `local` is the stored `zero`. */
export type UsageOverrideArgs =
  | { model: string; action: 'local' | 'clear' }
  | { model: string; action: 'alias'; aliasTo: string }
  | { model: string; action: 'custom'; inputPerMillionUsd: number; outputPerMillionUsd: number; cachedInputPerMillionUsd?: number; cacheWritePerMillionUsd?: number };

export interface UsageDeps {
  ports: UsagePorts;
  history: Omit<HistoryPorts, 'clock'>;
  db: ChatDb;
  /** The Carrier folder: `providers.json` and the engine's database are read from it. */
  folder: string;
  /** The chat's agents now, to tell which account a chat session ran on. */
  agents: () => ChatAgent[];
  env: NodeJS.ProcessEnv;
  home?: string;
}

/** One account to ask, or the local servers (account `local`), which no account stands for. */
function accountsOf(providers: Providers): { account: string; displayName?: string; target: QuotaTarget }[] {
  const asked = Object.entries(providers)
    .filter(([, a]) => a.provider === undefined) // an account on a local server has no quota of its own
    .map(([account, a]) => ({ account, ...(a.displayName !== undefined && { displayName: a.displayName }), target: { provider: a.harness, ...(a.configDir !== undefined && { configDir: a.configDir }), ...(a.command !== undefined && { command: a.command }) } satisfies QuotaTarget }));
  return [...asked, { account: 'local', displayName: 'Local servers', target: { provider: 'local' } }];
}

/**
 * What `usage` and `usageOverride` answer from the chat host: live quotas per account of `providers.json` and the history of what was
 * used, from the folders each account's CLI writes (its own config folder, else the environment's, else the CLI's default).
 */
export function createUsage({ ports, history: historyPorts, db, folder, agents, env, home = homedir() }: UsageDeps) {
  const quotas = createQuotas(ports);
  const history = createHistory({ ...historyPorts, clock: ports.clock }, { chat: db, engineDbFile: enginePlacesOf(folder).db });
  const overrides = createPriceOverrides(db, () => ports.clock.now());

  const rootsOf = (providers: Providers): HistoryRoots => {
    const roots: HistoryRoots = { claude: [], codex: [], agy: [] };
    for (const a of Object.values(providers)) {
      if (a.harness === 'claude') roots.claude.push(join(a.configDir ?? env.CLAUDE_CONFIG_DIR ?? join(home, '.claude'), 'projects'));
      else if (a.harness === 'codex') roots.codex.push(join(a.configDir ?? env.CODEX_HOME ?? join(home, '.codex'), 'sessions'));
      else roots.agy.push(join(home, '.gemini', 'antigravity-cli', 'conversations'));
    }
    return { claude: [...new Set(roots.claude)], codex: [...new Set(roots.codex)], agy: [...new Set(roots.agy)] };
  };

  return {
    async usage({ refresh, days = 30, provider = 'all', source = 'all', search, account }: UsageArgs) {
      const read = readProvidersFile(folder);
      if (read.ok === false) throw new ChatRefused(providersProblem(folder, read.errors));
      const providers = account === undefined ? read.providers : Object.fromEntries(Object.entries(read.providers).filter(([name]) => name === account));
      const asked = accountsOf(providers).filter((a) => account === undefined || a.account === account).filter((a) => provider === 'all' || a.target.provider === provider);
      const snapshots: (QuotaSnapshot & { account: string; displayName?: string })[] = await Promise.all(asked.map(async (a) => ({ account: a.account, ...(a.displayName !== undefined && { displayName: a.displayName }), ...(await quotas(a.target, { refresh })) })));
      const past = await history({ days, provider, source, ...(search !== undefined && { search }), ...(account !== undefined && { account }) }, { accounts: read.providers, agents: agents(), roots: rootsOf(providers) });
      return { checkedAt: ports.clock.now(), quotas: snapshots, summary: past.totals, daily: past.days, byModel: past.byModel, byWorkspace: past.byWorkspace, catalogModels: Object.keys(catalog) };
    },
    usageOverride(request: UsageOverrideArgs) {
      const stored: OverrideRequest =
        request.action === 'local' ? { model: request.model, action: 'zero' }
        : request.action === 'alias' ? { model: request.model, action: 'alias', aliasModel: request.aliasTo }
        : request.action === 'custom' ? { model: request.model, action: 'custom', inputUsdPerMillion: request.inputPerMillionUsd, outputUsdPerMillion: request.outputPerMillionUsd, ...(request.cachedInputPerMillionUsd !== undefined && { cachedInputUsdPerMillion: request.cachedInputPerMillionUsd }), ...(request.cacheWritePerMillionUsd !== undefined && { cacheWriteUsdPerMillion: request.cacheWritePerMillionUsd }) }
        : { model: request.model, action: 'clear' };
      try {
        overrides.set(stored);
      } catch (error) {
        if (error instanceof PriceOverrideInvalid) throw new ChatRefused(error.message);
        throw error;
      }
      return { model: request.model, action: request.action };
    },
  };
}
