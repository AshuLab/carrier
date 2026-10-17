import { formatDuration } from '../format/duration.ts';

export type PanelEpic = {
  repo: string;
  issue: number;
  status: 'running' | 'needs_human';
  stage: 'ship' | 'review' | 'fix' | null;
  /** Review round, null until the final PR is validated. */
  round: number | null;
  maxReviews: number;
  blockers: number;
  /** ms since epoch, when the epic entered its current stage. */
  stageSince: number;
  /** ms since epoch of the agent's last output; a different fact from the stage. */
  lastActivityAt: number | null;
  issueUrl: string;
  prUrl: string | null;
  lastError: string | null;
  needsHumanReason: string | null;
};

export type PanelSnapshot = {
  now: number;
  slots: { busy: number; total: number };
  /** Queued epics, oldest first. */
  queue: { repo: string; issue: number }[];
  epics: PanelEpic[];
  /** When this carrier process started (ms since epoch). */
  startedAt: number;
  /** How many repos are watched. */
  repos: number;
  /** When the next poll is due; null before the first is scheduled. */
  nextCheckAt: number | null;
  /** Why GitHub work is stalled right now (GitHub down, a profile rejected), null when all is well. */
  problem: string | null;
  /** The epics that ended ready for test, most recent first. */
  done: { repo: string; issue: number; prNumber: number | null; finishedAt: number | null }[];
};

// The reason and the error come from the agent's own output: no control character (ESC included) may reach the terminal.
const printable = (text: string) => text.replace(/[\x00-\x1f\x7f-\x9f]/g, ' ');

// The one-line-per-change form for a pipe (a terminal gets the dashboard). Pure: no ANSI.
export function renderPanel({ now, slots, queue, epics }: PanelSnapshot): string[] {
  const lines = [`carrier  slots ${slots.busy}/${slots.total}  queue ${queue.length}${queue.length > 0 ? `: ${queue.map((q) => `${q.repo}#${q.issue}`).join(', ')}` : ''}`];
  for (const e of epics) {
    const parts = [
      `${e.repo}#${e.issue}`,
      e.status === 'needs_human' ? 'NEEDS HUMAN' : (e.stage ?? 'starting'),
      ...(e.round === null ? [] : [`round ${e.round}/${e.maxReviews}`]),
      `blockers ${e.blockers}`,
      `in stage ${formatDuration(now - e.stageSince)}`,
      e.lastActivityAt === null ? 'no activity' : `activity ${formatDuration(now - e.lastActivityAt)} ago`,
    ];
    lines.push(parts.join('  '), `  issue ${e.issueUrl}${e.prUrl ? `  PR ${e.prUrl}` : ''}`);
    if (e.needsHumanReason) lines.push(`  reason: ${printable(e.needsHumanReason)}`);
    if (e.lastError) lines.push(`  error: ${printable(e.lastError)}`);
  }
  return lines;
}
