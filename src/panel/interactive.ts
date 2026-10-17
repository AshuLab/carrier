import { startKeys } from './keys.ts';
import { startPanel, type PanelOutput } from './panel.ts';
import { renderDashboard } from './dashboard.ts';
import type { PanelSnapshot } from './render.ts';
import { initialUi, itemsOf, onKey, settle, type Action } from './ui-state.ts';

/** What the keys can do. The program decides how: the panel only knows the names. */
export interface Controls {
  poll(): unknown;
  setPaused(paused: boolean): unknown;
  open(url: string): void;
  quit(): void;
  /** The last lines of the agent output of an execution. */
  logs(executionId: string, count: number): string[];
}

const logRows = 18;

/**
 * The dashboard with keys: select an epic, open it, read its agent's output, check GitHub now, pause intake, quit.
 * Every key redraws at once instead of waiting for the next second. Returns the stop function.
 */
export function startInteractivePanel({ snapshot, out, stdin, controls, now = Date.now, intervalMs }: {
  snapshot: () => PanelSnapshot;
  out: PanelOutput;
  stdin: Parameters<typeof startKeys>[0];
  controls: Controls;
  now?: () => number;
  intervalMs?: number;
}) {
  let ui = initialUi;
  const panel = startPanel(
    snapshot,
    out,
    intervalMs,
    (s, columns) => {
      ui = settle(ui, s, now());
      const executionId = ui.mode === 'logs' ? itemsOf(s).find((i) => i.key === ui.selected)?.executionId : undefined;
      return renderDashboard(s, { columns, ui, logLines: executionId ? controls.logs(executionId, logRows) : [] });
    },
  );
  const perform = (action: Action | undefined) => {
    if (action?.type === 'open') controls.open(action.url);
    else if (action?.type === 'poll') void controls.poll();
    else if (action?.type === 'pause') void controls.setPaused(action.paused);
    else if (action?.type === 'quit') controls.quit();
  };
  const stopKeys = startKeys(stdin, (key) => {
    const next = onKey(ui, key, snapshot(), now());
    ui = next.ui;
    perform(next.action);
    panel.redraw();
  });
  return () => {
    stopKeys();
    panel();
  };
}
