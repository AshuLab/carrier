import { renderDashboard } from './dashboard.ts';
import { renderPanel, type PanelEpic, type PanelSnapshot } from './render.ts';

export interface PanelOutput {
  write(text: string): unknown;
  isTTY?: boolean;
  columns?: number;
}

// What a person reads as "the state changed": durations tick every second and do not count.
const stateOf = (e: PanelEpic) => [e.status, e.stage, e.round, e.blockers, e.needsHumanReason, e.lastError].join('|');

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
  render: (s: PanelSnapshot, columns: number | undefined) => string[] = (s, columns) => renderDashboard(s, { columns }),
): (() => void) & { redraw: () => void } {
  let drawn = 0;
  const seen = new Map<string, string>();
  let queueSeen = '';

  // The panel owns the screen, so the cursor is hidden while it runs and always given back, also when the process dies on its own.
  const hideCursor = '\x1b[?25l';
  const showCursor = '\x1b[?25h';
  const restoreOnExit = () => out.write(showCursor);
  if (out.isTTY) process.once('exit', restoreOnExit);

  const redraw = (s: PanelSnapshot) => {
    // Lines wider than the terminal would wrap and break the cursor-up count; the dashboard cuts them itself.
    const lines = render(s, out.columns);
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
      out.write(`${at} ${renderPanel({ ...s, epics: [e] }).slice(1).map((l) => l.trim()).join(' | ')}\n`);
    }
  };

  const tick = () => (out.isTTY ? redraw : emitChanges)(snapshot());
  tick();
  const timer = setInterval(tick, intervalMs);
  const stop = () => {
    clearInterval(timer);
    if (out.isTTY) {
      process.removeListener('exit', restoreOnExit);
      out.write(showCursor);
    }
  };
  return Object.assign(stop, { redraw: tick });
}
