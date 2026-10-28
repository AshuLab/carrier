import { createScopedLogger } from '@ashulab/universal-logger';
import { startKeys } from './keys.ts';
import { startPanel, type PanelOutput } from './panel.ts';
import { renderDashboard } from './dashboard.ts';
import type { PanelSnapshot } from '../../status/types.ts';
import type { DetailProvider } from './history.ts';
import { initialUi, itemsOf, onKey, settle, toastFor, type Action } from './ui-state.ts';

/** What the keys can do. The program decides how: the panel only knows the names. */
export interface Controls {
  poll(): unknown;
  setPaused(paused: boolean): unknown;
  open(url: string): void;
  quit(): void;
  /** The last lines of the agent output of an execution. */
  logs(executionId: string, count: number): string[];
  /** The stages of an epic and how each went; the panel asks it again only when the epic changed. */
  detail?: DetailProvider;
  /** Starts a waiting epic on the options chosen; a role left out takes its default. Absent against an engine without the `agentOptions` capability: the panel then offers no choice. */
  chooseOptions?(repo: string, issue: number, chosen: { author?: string; reviewer?: string }): unknown;
}

const logRows = 18;
const log = createScopedLogger('panel');
/** The engine's expected refusals of `chooseOptions`, in the panel's words. */
const refusalWords: Record<string, string> = {
  'not waiting': 'Already started on its defaults',
  'unknown option': 'That option is not in the configuration',
  'unknown epic': 'That epic is gone',
  'github unavailable': 'GitHub is not answering: it starts on its own when it does',
};


/**
 * The dashboard with keys: select an epic, open it, read its agent's output, check GitHub now, pause intake, choose the options of a waiting epic, quit.
 * Every key redraws at once instead of waiting for the next second. Returns the stop function.
 */
export function startInteractivePanel({ snapshot, out, stdin, controls, now = Date.now, intervalMs, quit }: {
  snapshot: () => PanelSnapshot;
  out: PanelOutput;
  stdin: Parameters<typeof startKeys>[0];
  controls: Controls;
  now?: () => number;
  intervalMs?: number;
  /** What `q` does, as the screens say it; see `DashboardOptions.quit`. */
  quit?: 'stop' | 'leave';
}) {
  let ui = initialUi;
  const canChoose = controls.chooseOptions !== undefined;
  const panel = startPanel(
    snapshot,
    out,
    intervalMs,
    (s, columns) => {
      ui = settle(ui, s, now());
      const executionId = ui.mode === 'logs' ? itemsOf(s).find((i) => i.key === ui.selected)?.executionId : undefined;
      return renderDashboard(s, { columns, ui, logLines: executionId ? controls.logs(executionId, logRows) : [], activity: controls.logs, detail: controls.detail, quit, canChoose });
    },
  );
  const perform = (action: Action | undefined) => {
    if (action?.type === 'open') controls.open(action.url);
    else if (action?.type === 'poll') void controls.poll();
    else if (action?.type === 'pause') void controls.setPaused(action.paused);
    else if (action?.type === 'choose') {
      // The engine says no when the deadline won the race, and a rejection nobody catches ends the process: tell the person instead.
      Promise.resolve(controls.chooseOptions?.(action.repo, action.issue, { author: action.author, reviewer: action.reviewer })).catch((error) => {
        const reason = error instanceof Error ? error.message : String(error);
        // A refusal is the engine answering; anything else is a failure.
        if (Object.hasOwn(refusalWords, reason)) log.info('the engine refused the chosen options', { reason, repo: action.repo, epic: action.issue });
        else log.error('could not start the epic on the chosen options', error, { repo: action.repo, epic: action.issue });
        ui = { ...ui, toast: { text: refusalWords[reason] ?? `Could not start it: ${reason}`, until: now() + toastFor } };
        panel.redraw();
      });
    }
    else if (action?.type === 'quit') controls.quit();
  };
  const stopKeys = startKeys(stdin, (key) => {
    const next = onKey(ui, key, snapshot(), now(), canChoose);
    ui = next.ui;
    perform(next.action);
    panel.redraw();
  });
  return () => {
    stopKeys();
    panel();
  };
}
