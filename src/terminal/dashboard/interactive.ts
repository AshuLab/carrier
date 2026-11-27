import { startKeys } from './keys.ts';
import { startPanel, type PanelOutput } from './panel.ts';
import { colorWanted, renderDashboard } from './dashboard.ts';
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
  /** Hides a closed (merged or cancelled) epic for good; absent, the panel does not offer the key. */
  dismiss?(repo: string, issue: number): Promise<{ ok: true } | { ok: false; reason: string }>;
  /** Starts a stopped epic again on the agents it had; resolves when it has started (the engine takes up to 30 seconds) or with the reason it refused. Absent: the key is not offered. */
  resume?(repo: string, issue: number): Promise<{ ok: true } | { ok: false; reason: string }>;
}

const logRows = 18;

/**
 * The dashboard with keys: select an epic, open it, read its agent's output, check GitHub now, pause intake, quit.
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
  const panel = startPanel(
    snapshot,
    out,
    intervalMs,
    (s, columns, rows) => {
      ui = settle(ui, s, now());
      const executionId = ui.mode === 'logs' ? itemsOf(s, ui.closedOpen).find((i) => i.key === ui.selected)?.executionId : undefined;
      return renderDashboard(s, { columns, rows, color: colorWanted(), ui, dismiss: controls.dismiss !== undefined, resume: controls.resume !== undefined, logLines: executionId ? controls.logs(executionId, logRows) : [], activity: controls.logs, detail: controls.detail, quit });
    },
  );
  let stopped = false;
  // The answer comes later than the key: it says so in the toast, whatever the person is looking at by then.
  const say = (text: string) => {
    if (stopped) return;
    ui = { ...ui, toast: { text, until: now() + toastFor } };
    panel.redraw();
  };
  const dismiss = (repo: string, issue: number) => {
    controls.dismiss!(repo, issue).then(
      (result) => say(result.ok ? `Dismissed ${repo}#${issue}` : result.reason),
      (error: unknown) => say(`Could not dismiss ${repo}#${issue}: ${error instanceof Error ? error.message : String(error)}`),
    );
  };
  const resuming = new Set<string>(); // an epic whose resume has not answered: a second one would only be refused
  const resume = (repo: string, issue: number) => {
    const key = `${repo}#${issue}`;
    if (resuming.has(key)) return;
    resuming.add(key);
    controls.resume!(repo, issue).then(
      (result) => say(result.ok ? `Resumed ${key}` : result.reason),
      (error: unknown) => say(`Could not resume ${key}: ${error instanceof Error ? error.message : String(error)}`),
    ).finally(() => resuming.delete(key));
  };
  const perform = (action: Action | undefined) => {
    if (action?.type === 'open') controls.open(action.url);
    else if (action?.type === 'poll') void controls.poll();
    else if (action?.type === 'pause') void controls.setPaused(action.paused);
    else if (action?.type === 'dismiss') dismiss(action.repo, action.issue);
    else if (action?.type === 'resume') resume(action.repo, action.issue);
    else if (action?.type === 'quit') controls.quit();
  };
  const stopKeys = startKeys(stdin, (key) => {
    const next = onKey(ui, key, snapshot(), now(), { canDismiss: controls.dismiss !== undefined, canResume: controls.resume !== undefined });
    ui = next.ui;
    perform(next.action);
    panel.redraw();
  });
  return () => {
    stopped = true;
    stopKeys();
    panel();
  };
}
