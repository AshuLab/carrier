import { formatDuration } from '../../format/duration.ts';
import { printable } from './printable.ts';
import type { PanelSnapshot } from '../../status/types.ts';
import { finishedSections } from './ui-state.ts';

// The one-line-per-change form for a pipe (a terminal gets the dashboard). Pure: no ANSI.
export function renderPanel(s: PanelSnapshot): string[] {
  const { now, slots, queue, epics } = s;
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
  for (const { name, rows, more } of finishedSections(s)) {
    const kind = name === 'DONE' ? 'done' : 'cancelled';
    for (const f of rows) lines.push(`${kind}  ${f.repo}#${f.issue}${f.prNumber === null ? '' : `  PR #${f.prNumber}`}  ${formatDuration(Math.max(0, now - f.finishedAt))} ago${f.title ? `  ${printable(f.title)}` : ''}${f.cancelReason ? `  reason: ${printable(f.cancelReason)}` : ''}`);
    if (more > 0) lines.push(`${kind}  +${more} more`);
  }
  return lines;
}
