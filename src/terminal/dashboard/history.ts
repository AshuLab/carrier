import { formatDuration } from '../../format/duration.ts';
import type { SessionsReply } from '../../control/replies.ts';
import type { PanelEpic } from '../../status/types.ts';

export type Sessions = SessionsReply['sessions'];
/**
 * What the panel asks for an epic's stages; null when nothing is known about it. `undefined` is "still being asked":
 * the answer is not remembered and the last one stays on screen, so a provider that answers later (over the socket) can be asked again.
 */
export type DetailProvider = (repo: string, issue: number) => Sessions | null | undefined;

// ponytail: entries of epics that left the panel stay until the provider is dropped; a prune if a long run ever shows it.
const caches = new WeakMap<DetailProvider, Map<string, { signature: string; detail: Sessions | null }>>();

/** An epic's detail, asked again only when its stage, round, status, blockers or latest execution changed (a finished epic has only the last). */
export function detailOf(provider: DetailProvider, e: Pick<PanelEpic, 'repo' | 'issue'> & Partial<Pick<PanelEpic, 'stage' | 'round' | 'status' | 'blockers'>> & { executionId?: string | null }): Sessions | null {
  const cache = caches.get(provider) ?? new Map();
  caches.set(provider, cache);
  const key = `${e.repo}#${e.issue}`;
  const signature = [e.stage, e.round, e.status, e.blockers, e.executionId].join('|');
  const hit = cache.get(key);
  if (hit?.signature === signature) return hit.detail;
  const detail = provider(e.repo, e.issue);
  if (detail === undefined) return hit?.detail ?? null;
  cache.set(key, { signature, detail });
  return detail;
}

type Paint = (text: string, ...styles: ('bold' | 'dim' | 'cyan' | 'green' | 'yellow')[]) => string;
const marks = { completed: ['✓', 'green'], changes_requested: ['↻ changes', 'yellow'], needs_human: ['▲ needs you', 'yellow'] } as const;

/** "ship ✓ 14m · review ↻ changes round 1 4m · [fix] 2m": oldest first, the running stage in brackets; the oldest are dropped to fit `width`. */
export function historyLine(sessions: Sessions, now: number, paint: Paint, width: number): string {
  const parts = [...sessions].reverse().map((x) => {
    const took = formatDuration((x.finishedAt ?? now) - x.startedAt);
    const round = x.round === null ? '' : ` round ${x.round}`;
    if (x.status === 'running') return { shown: `[${x.stage}]${round} ${took}`, styled: paint(`[${x.stage}]`, 'bold', 'cyan') + `${round} ${took}` };
    const [mark, color] = x.failure ? ([`✗ ${x.failure.kind}`, 'yellow'] as const) : x.result ? marks[x.result.outcome] : (['', 'dim'] as const);
    return { shown: `${x.stage}${mark ? ` ${mark}` : ''}${round} ${took}`, styled: `${x.stage}${mark ? ` ${paint(mark, color)}` : ''}${round} ${took}` };
  });
  const separator = ' · ';
  const length = (list: typeof parts) => list.reduce((n, p) => n + p.shown.length, 0) + separator.length * (list.length - 1);
  let dropped = false;
  while (parts.length > 1 && length(parts) + (dropped ? 2 : 0) > width) {
    parts.shift();
    dropped = true;
  }
  return `${dropped ? '… ' : ''}${parts.map((p) => p.styled).join(paint(separator, 'dim'))}`;
}
