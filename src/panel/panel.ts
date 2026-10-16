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
export function startPanel(snapshot: () => PanelSnapshot, out: PanelOutput = process.stdout, intervalMs = 1000): () => void {
  let drawn = 0;
  const seen = new Map<string, string>();
  let queueSeen = '';

  const redraw = (s: PanelSnapshot) => {
    // Lines wider than the terminal would wrap and break the cursor-up count.
    const lines = renderPanel(s).map((l) => (out.columns ? l.slice(0, out.columns) : l));
    out.write(`${drawn > 0 ? `\x1b[${drawn}A` : ''}${lines.map((l) => `\r\x1b[2K${l}\n`).join('')}\x1b[J`);
    drawn = lines.length;
  };

  const emitChanges = (s: PanelSnapshot) => {
    const at = new Date(s.now).toISOString();
    const queue = `${s.slots.busy}/${s.slots.total}|${s.queue.map((q) => `${q.repo}#${q.issue}`).join(',')}`;
    if (queue !== queueSeen) {
      queueSeen = queue;
      out.write(`${at} slots ${s.slots.busy}/${s.slots.total} cola ${s.queue.length}${s.queue.length > 0 ? `: ${s.queue.map((q) => `${q.repo}#${q.issue}`).join(', ')}` : ''}\n`);
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
  return () => clearInterval(timer);
}
