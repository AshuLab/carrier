import type { PanelFinished, PanelSnapshot } from '../../status/types.ts';

/** A row the person can select, in the order the dashboard shows it. `closed` is a merged or cancelled epic, the only kind that can be dismissed; `header` is the CLOSED heading, which opens and folds the section. */
export type Item = { key: string; repo: string; issue: number; url: string; executionId: string | null; closed: boolean; header?: true;
  /** A row of NEEDS YOU: an epic stopped for a person, the only kind that can be resumed; `usage` when it stopped on the agent's quota. */
  stopped?: true; usage?: true };

/** The key of the CLOSED heading as a selectable row: not an `owner/name#issue`, so no epic can have it. */
export const closedKey = 'closed';

/** How many queued epics the dashboard lists before "… and N more"; selection only reaches what is listed. */
export const maxListed = 5;

/** How many finished epics of each kind the panel lists before "+N more"; selection only reaches what is listed. */
export const maxFinished = 10;

/** The DONE and CANCELLED sections that have something to show, each cut to `maxFinished` rows with the count of the rest. */
export function finishedSections(s: PanelSnapshot): { name: 'DONE' | 'CANCELLED'; status: PanelFinished['status']; rows: PanelFinished[]; more: number }[] {
  const all = s.finished ?? [];
  return ([['DONE', 'merged'], ['CANCELLED', 'cancelled']] as const)
    .map(([name, status]) => ({ name, status, all: all.filter((f) => f.status === status) }))
    .filter((x) => x.all.length > 0)
    .map(({ name, status, all }) => ({ name, status, rows: all.slice(0, maxFinished), more: Math.max(0, all.length - maxFinished) }));
}

const issueUrl = (repo: string, issue: number) => `https://github.com/${repo}/issues/${issue}`;

/** How many merged and cancelled epics the snapshot carries: the count of the CLOSED section, listed or not. */
export const closedCount = (s: PanelSnapshot) => (s.finished ?? []).length;

/** The rows that can be selected now: the CLOSED heading after the live ones, and the closed epics under it only while the section is open. */
export function itemsOf(s: PanelSnapshot, closedOpen: boolean): Item[] {
  const running = s.epics.filter((e) => e.status === 'running');
  const needsYou = s.epics.filter((e) => e.status === 'needs_human');
  const prUrl = (d: { repo: string; issue: number; prNumber: number | null }) => (d.prNumber === null ? issueUrl(d.repo, d.issue) : `https://github.com/${d.repo}/pull/${d.prNumber}`);
  const item = (x: { repo: string; issue: number }, url: string, executionId: string | null, closed = false): Item => ({ key: `${x.repo}#${x.issue}`, repo: x.repo, issue: x.issue, url, executionId, closed });
  return [
    ...running.map((e) => item(e, e.prUrl ?? e.issueUrl, e.executionId)),
    ...s.queue.slice(0, maxListed).map((q) => item(q, issueUrl(q.repo, q.issue), null)),
    ...needsYou.map((e) => ({ ...item(e, e.prUrl ?? e.issueUrl, e.executionId), stopped: true as const, ...(e.needsHumanCode?.startsWith('epic.stop.usageLimit') && { usage: true as const }) })),
    ...s.done.map((d) => item(d, prUrl(d), d.executionId)),
    ...(closedCount(s) > 0 ? [{ key: closedKey, repo: '', issue: 0, url: '', executionId: null, closed: false, header: true } satisfies Item] : []),
    ...(closedOpen ? finishedSections(s).flatMap((x) => x.rows).map((d) => item(d, prUrl(d), d.executionId, true)) : []),
  ];
}

export type UiState = {
  /** `owner/name#issue` of the selected row, null when none. Kept by key so it follows the epic as the list changes. */
  selected: string | null;
  mode: 'dashboard' | 'logs' | 'help';
  toast: { text: string; until: number } | null;
  /** The CLOSED section (merged and cancelled epics) is open. It starts closed: they are done, and the rows below would push the live ones out of view. */
  closedOpen: boolean;
  /** `owner/name#issue` of the stopped epic whose resume waits for a second R: a request that spends credits asks once more. Absent: nothing waits. */
  confirm?: string;
};

export const initialUi: UiState = { selected: null, mode: 'dashboard', toast: null, closedOpen: false };

export type Key = { name?: string; ctrl?: boolean; sequence?: string };
export type Action =
  | { type: 'open'; url: string }
  | { type: 'poll' }
  | { type: 'pause'; paused: boolean }
  | { type: 'dismiss'; repo: string; issue: number }
  | { type: 'resume'; repo: string; issue: number }
  | { type: 'quit' };

export const toastFor = 3000;
/** The engine answers a resume when the epic has started again, up to 30 seconds later: the toast that says it is under way stays that long. */
export const resumeToastFor = 35_000;

/** Pure: what a key does to the screen state, and what it asks the program to do. */
export function onKey(ui: UiState, key: Key, s: PanelSnapshot, now: number, { canDismiss = false, canResume = false }: { canDismiss?: boolean; canResume?: boolean } = {}): { ui: UiState; action?: Action } {
  const items = itemsOf(s, ui.closedOpen);
  const say = (text: string): UiState => ({ ...ui, toast: { text, until: now + toastFor } });
  const raw = key.sequence === '?' ? '?' : key.name;
  const name = raw === 'j' ? 'down' : raw === 'k' ? 'up' : raw; // vim keys move too

  // r twice resumes; any other key between them withdraws the first.
  if (name !== 'r' && ui.confirm !== undefined) {
    const { confirm: _asked, ...rest } = ui;
    ui = rest;
  }

  if ((key.ctrl && name === 'c') || name === 'q') return { ui, action: { type: 'quit' } };
  if (name === '?') return { ui: { ...ui, mode: ui.mode === 'help' ? 'dashboard' : 'help' } };
  if (ui.mode !== 'dashboard') {
    // Help and logs are one keypress away from the dashboard and take no other keys.
    return name === 'escape' || (ui.mode === 'logs' && name === 'l') ? { ui: { ...ui, mode: 'dashboard' } } : { ui };
  }

  const at = items.findIndex((i) => i.key === ui.selected);
  const current = at === -1 ? undefined : items[at];
  if (name === 'r') {
    if (!canResume) return { ui };
    if (!current?.stopped) return { ui: say('Only a stopped epic (NEEDS YOU) can be resumed · c checks GitHub now') };
    if (ui.confirm !== current.key) return { ui: { ...ui, confirm: current.key } };
    const { confirm: _asked, ...rest } = ui;
    return { ui: { ...rest, toast: { text: `Resuming ${current.key}…`, until: now + resumeToastFor } }, action: { type: 'resume', repo: current.repo, issue: current.issue } };
  }
  switch (name) {
    case 'down':
      return { ui: { ...ui, selected: items.length === 0 ? null : items[Math.min(at + 1, items.length - 1)]!.key } };
    case 'up':
      return { ui: { ...ui, selected: items.length === 0 ? null : items[at <= 0 ? 0 : at - 1]!.key } };
    case 'return':
      if (current?.header) return { ui: { ...ui, closedOpen: !ui.closedOpen } };
      return current ? { ui: say(`Opening ${current.url.replace('https://github.com/', '')}`), action: { type: 'open', url: current.url } } : { ui: say('Select an epic first (↑/↓)') };
    case 'l':
      if (!current) return { ui: say('Select an epic first (↑/↓)') };
      return current.executionId ? { ui: { ...ui, mode: 'logs' } } : { ui: say('That one has no agent output yet') };
    case 'c':
      return { ui: say('Checking GitHub now…'), action: { type: 'poll' } };
    case 'p':
      return s.paused ? { ui: say('Unpaused: taking epics again'), action: { type: 'pause', paused: false } } : { ui: say('Paused: no new epics will start'), action: { type: 'pause', paused: true } };
    case 'right':
      return current?.header ? { ui: { ...ui, closedOpen: true } } : { ui };
    case 'left':
    case 'f': {
      if (closedCount(s) === 0) return { ui: say('No closed epics') };
      // ← only folds, from the heading or a row under it; f flips the section from anywhere.
      const open = name === 'left' ? false : !ui.closedOpen;
      if (name === 'left' && !current?.header && !current?.closed) return { ui };
      // Folding the section under the selection moves it to the heading, where it can be opened again.
      return { ui: { ...ui, closedOpen: open, selected: !open && current?.closed ? closedKey : ui.selected } };
    }
    case 'd': {
      if (!canDismiss) return { ui };
      if (!current?.closed) return { ui: say('Only closed epics can be dismissed') };
      // The row leaves with the next snapshot: the selection goes to its neighbour now, so it does not jump to the first row.
      const next = items[at + 1] ?? items[at - 1];
      return { ui: { ...ui, selected: next?.key ?? null }, action: { type: 'dismiss', repo: current.repo, issue: current.issue } };
    }
    default:
      return { ui };
  }
}

/** The state to draw with: a selection that no longer exists moves to the first row, a toast past its time is dropped, logs of nothing go back. */
export function settle(ui: UiState, s: PanelSnapshot, now: number): UiState {
  const items = itemsOf(s, ui.closedOpen);
  const current = items.find((i) => i.key === ui.selected);
  const gone = ui.mode === 'logs' && !current?.executionId; // logs of nothing
  // A resume that waits for its second R only waits on the row it was asked for, and only while that row is still stopped.
  const { confirm: asked, ...rest } = ui;
  return {
    ...rest,
    ...(asked !== undefined && current?.stopped && current.key === asked && { confirm: asked }),
    selected: current ? ui.selected : (items[0]?.key ?? null), // something is always selected, so the keys always act on a visible row
    mode: gone ? 'dashboard' : ui.mode,
    toast: ui.toast && ui.toast.until > now ? ui.toast : null,
  };
}
