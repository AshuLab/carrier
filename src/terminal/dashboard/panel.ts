import { colorWanted, renderDashboard } from './dashboard.ts';
import { renderPanel } from './plain.ts';
import type { PanelEpic, PanelSnapshot } from '../../status/types.ts';

export interface PanelOutput {
  write(text: string): unknown;
  isTTY?: boolean;
  columns?: number;
  rows?: number;
  /** A terminal says when its size changed (`process.stdout` does, as 'resize'); what has none is not redrawn until its next tick. */
  on?(event: 'resize', listener: () => void): unknown;
  off?(event: 'resize', listener: () => void): unknown;
}

// What a person reads as "the state changed": durations tick every second and do not count.
const stateOf = (e: PanelEpic) => [e.status, e.stage, e.round, e.blockers, e.needsHumanReason, e.lastError, e.retryAt].join('|');

/**
 * Shows the snapshot on `out` every `intervalMs`: redrawn in place with ANSI on a terminal, one plain line
 * per state change otherwise. No input handling: Ctrl+C is the only way to stop the process.
 * Returns the stop function.
 */
export function startPanel(
  snapshot: () => PanelSnapshot,
  out: PanelOutput = process.stdout,
  intervalMs = 1000,
  /** What a terminal is shown; the dashboard unless the caller draws its own (with a selection, say). */
  render: (s: PanelSnapshot, columns: number | undefined, rows: number | undefined) => string[] = (s, columns, rows) => renderDashboard(s, { columns, rows, color: colorWanted() }),
): (() => void) & { redraw: () => void } {
  let drawn = 0;
  const seen = new Map<string, string>();
  let queueSeen = '';
  let finishedSeen = '';

  // The panel owns the screen, so the cursor is hidden while it runs and always given back, also when the process dies on its own.
  const hideCursor = '\x1b[?25l';
  const showCursor = '\x1b[?25h';
  const restoreOnExit = () => out.write(showCursor);
  if (out.isTTY) process.once('exit', restoreOnExit);

  const redraw = (s: PanelSnapshot) => {
    // Lines wider than the terminal would wrap and break the cursor-up count; the dashboard cuts them itself.
    // A frame taller than the terminal would scroll, and the cursor-up count could not reach its top: whoever draws is told the rows, and a renderer that ignores them is cut here.
    const lines = render(s, out.columns, out.rows);
    if (out.rows !== undefined && out.rows > 1 && lines.length >= out.rows) lines.length = out.rows - 1;
    out.write(`${drawn > 0 ? `\x1b[${drawn}A` : hideCursor}${lines.map((l) => `\r\x1b[2K${l}\n`).join('')}\x1b[J`);
    drawn = lines.length;
  };

  const emitChanges = (s: PanelSnapshot) => {
    const at = new Date(s.now).toISOString();
    const queue = `${s.slots.busy}/${s.slots.total}|${s.queue.map((q) => `${q.repo}#${q.issue}`).join(',')}`;
    if (queue !== queueSeen) {
      queueSeen = queue;
      out.write(`${at} slots ${s.slots.busy}/${s.slots.total} queue ${s.queue.length}${s.queue.length > 0 ? `: ${s.queue.map((q) => `${q.repo}#${q.issue}`).join(', ')}` : ''}\n`);
    }
    for (const e of s.epics) {
      const key = `${e.repo}#${e.issue}`;
      if (seen.get(key) === stateOf(e)) continue;
      seen.set(key, stateOf(e));
      out.write(`${at} ${renderPanel({ ...s, epics: [e], finished: [] }).slice(1).map((l) => l.trim()).join(' | ')}\n`);
    }
    // The finished rows when the set changes: their "ago" ticks and does not count.
    const finished = (s.finished ?? []).map((f) => `${f.repo}#${f.issue}`).join(',');
    if (finished !== finishedSeen) {
      finishedSeen = finished;
      for (const l of renderPanel({ ...s, epics: [] }).slice(1)) out.write(`${at} ${l}\n`);
    }
  };

  const tick = () => (out.isTTY ? redraw : emitChanges)(snapshot());
  tick();
  const timer = setInterval(tick, intervalMs);
  // The old frame was laid out for another size and the terminal reflowed it, so the cursor-up count no longer reaches its top: clear the screen and draw from the corner, now rather than at the next tick.
  const onResize = () => {
    out.write('\x1b[2J\x1b[H');
    drawn = 0;
    tick();
  };
  if (out.isTTY) out.on?.('resize', onResize);
  const stop = () => {
    clearInterval(timer);
    out.off?.('resize', onResize);
    if (out.isTTY) {
      process.removeListener('exit', restoreOnExit);
      out.write(showCursor);
    }
  };
  return Object.assign(stop, { redraw: tick });
}
