import { formatDuration } from '../../format/duration.ts';
import { printable } from './printable.ts';
import type { PanelSnapshot } from '../../status/types.ts';

// The one-line-per-change form for a pipe (a terminal gets the dashboard). Pure: no ANSI.
export function renderPanel({ now, slots, queue, epics }: PanelSnapshot): string[] {
  const lines = [`carrier  slots ${slots.busy}/${slots.total}  queue ${queue.length}${queue.length > 0 ? `: ${queue.map((q) => `${q.repo}#${q.issue}`).join(', ')}` : ''}`];
  for (const e of epics) {
    const parts = [
      `${e.repo}#${e.issue}`,
      e.status === 'needs_human' ? 'NEEDS HUMAN' : (e.stage ?? 'starting'),
      ...(e.round === null ? [] : [`round ${e.round}/${e.maxReviews}`]),
      ...(e.slices && e.slices.total > 0 ? [`slices ${e.slices.done}/${e.slices.total}`] : []),
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
