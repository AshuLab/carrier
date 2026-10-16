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
};

// Pure: the same snapshot always gives the same lines, with no ANSI.
export function renderPanel({ now, slots, queue, epics }: PanelSnapshot): string[] {
  const lines = [`carrier  slots ${slots.busy}/${slots.total}  cola ${queue.length}${queue.length > 0 ? `: ${queue.map((q) => `${q.repo}#${q.issue}`).join(', ')}` : ''}`];
  for (const e of epics) {
    const parts = [
      `${e.repo}#${e.issue}`,
      e.status === 'needs_human' ? 'NEEDS HUMAN' : (e.stage ?? 'iniciando'),
      ...(e.round === null ? [] : [`ronda ${e.round}/${e.maxReviews}`]),
      `blockers ${e.blockers}`,
      `en etapa ${formatDuration(now - e.stageSince)}`,
      e.lastActivityAt === null ? 'sin actividad' : `actividad hace ${formatDuration(now - e.lastActivityAt)}`,
    ];
    lines.push(parts.join('  '), `  issue ${e.issueUrl}${e.prUrl ? `  PR ${e.prUrl}` : ''}`);
    if (e.needsHumanReason) lines.push(`  motivo: ${e.needsHumanReason}`);
    if (e.lastError) lines.push(`  error: ${e.lastError}`);
  }
  return lines;
}
