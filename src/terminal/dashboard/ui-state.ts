import type { PanelEpic, PanelFinished, PanelSnapshot } from '../../status/types.ts';

/** A row the person can select, in the order the dashboard shows it. */
export type Item = { key: string; url: string; executionId: string | null };

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

export function itemsOf(s: PanelSnapshot): Item[] {
  const running = s.epics.filter((e) => e.status === 'running');
  const needsYou = s.epics.filter((e) => e.status === 'needs_human');
  return [
    ...running.map((e) => ({ key: `${e.repo}#${e.issue}`, url: e.prUrl ?? e.issueUrl, executionId: e.executionId })),
    ...s.queue.slice(0, maxListed).map((q) => ({ key: `${q.repo}#${q.issue}`, url: issueUrl(q.repo, q.issue), executionId: null })),
    ...needsYou.map((e) => ({ key: `${e.repo}#${e.issue}`, url: e.prUrl ?? e.issueUrl, executionId: e.executionId })),
    ...[...s.done, ...finishedSections(s).flatMap((x) => x.rows)].map((d) => ({ key: `${d.repo}#${d.issue}`, url: d.prNumber === null ? issueUrl(d.repo, d.issue) : `https://github.com/${d.repo}/pull/${d.prNumber}`, executionId: d.executionId })),
  ];
}

/** An epic that is waiting for its option choice, found by the key of a row. */
export const waitingEpic = (s: PanelSnapshot, key: string | null): PanelEpic | undefined =>
  s.epics.find((e) => `${e.repo}#${e.issue}` === key && e.status === 'running' && e.options !== undefined && e.options.choiceDeadline !== null);

export type UiState = {
  /** `owner/name#issue` of the selected row, null when none. Kept by key so it follows the epic as the list changes. */
  selected: string | null;
  mode: 'dashboard' | 'logs' | 'help' | 'choose';
  /** In 'choose' mode: the role the arrows are on and the option shown for each. */
  choice?: { role: 'author' | 'reviewer'; author: string; reviewer: string };
  toast: { text: string; until: number } | null;
};

export const initialUi: UiState = { selected: null, mode: 'dashboard', toast: null };

export type Key = { name?: string; ctrl?: boolean; sequence?: string };
export type Action =
  | { type: 'open'; url: string }
  | { type: 'poll' }
  | { type: 'pause'; paused: boolean }
  /** Without a role the epic starts on its defaults. */
  | { type: 'choose'; repo: string; issue: number; author?: string; reviewer?: string }
  | { type: 'quit' };

const toastFor = 3000;

/** Pure: what a key does to the screen state, and what it asks the program to do. */
export function onKey(ui: UiState, key: Key, s: PanelSnapshot, now: number, canChoose = false): { ui: UiState; action?: Action } {
  const items = itemsOf(s);
  const say = (text: string): UiState => ({ ...ui, toast: { text, until: now + toastFor } });
  const raw = key.sequence === '?' ? '?' : key.name;
  const name = raw === 'j' ? 'down' : raw === 'k' ? 'up' : raw; // vim keys move too

  if ((key.ctrl && name === 'c') || name === 'q') return { ui, action: { type: 'quit' } };
  if (ui.mode === 'choose') return chooseKey(ui, name, s);
  if (name === '?') return { ui: { ...ui, mode: ui.mode === 'help' ? 'dashboard' : 'help' } };
  if (ui.mode !== 'dashboard') {
    // Help and logs are one keypress away from the dashboard and take no other keys.
    return name === 'escape' || (ui.mode === 'logs' && name === 'l') ? { ui: { ...ui, mode: 'dashboard' } } : { ui };
  }

  const at = items.findIndex((i) => i.key === ui.selected);
  const current = at === -1 ? undefined : items[at];
  switch (name) {
    case 'down':
      return { ui: { ...ui, selected: items.length === 0 ? null : items[Math.min(at + 1, items.length - 1)]!.key } };
    case 'up':
      return { ui: { ...ui, selected: items.length === 0 ? null : items[at <= 0 ? 0 : at - 1]!.key } };
    case 'return':
      return current ? { ui: say(`Opening ${current.url.replace('https://github.com/', '')}`), action: { type: 'open', url: current.url } } : { ui: say('Select an epic first (↑/↓)') };
    case 'l':
      if (!current) return { ui: say('Select an epic first (↑/↓)') };
      return current.executionId ? { ui: { ...ui, mode: 'logs' } } : { ui: say('That one has no agent output yet') };
    case 'r':
      return { ui: say('Checking GitHub now…'), action: { type: 'poll' } };
    case 'o': {
      const waiting = canChoose ? waitingEpic(s, ui.selected) : undefined;
      if (!waiting?.options || waiting.options.names.length < 2) return { ui };
      return { ui: { ...ui, mode: 'choose', choice: { role: 'author', author: waiting.options.author ?? waiting.options.names[0]!, reviewer: waiting.options.reviewer ?? waiting.options.names[0]! } } };
    }
    case 'a': {
      const waiting = canChoose ? waitingEpic(s, ui.selected) : undefined;
      return waiting ? { ui: say(`Starting ${ui.selected} on its defaults`), action: { type: 'choose', repo: waiting.repo, issue: waiting.issue } } : { ui };
    }
    case 'p':
      return s.paused ? { ui: say('Resumed: taking epics again'), action: { type: 'pause', paused: false } } : { ui: say('Paused: no new epics will start'), action: { type: 'pause', paused: true } };
    default:
      return { ui };
  }
}

/** The keys of the choice mode: ↑↓ move between the roles, ←→ change the option of the one they are on, enter sends, esc leaves. */
function chooseKey(ui: UiState, name: string | undefined, s: PanelSnapshot): { ui: UiState; action?: Action } {
  const waiting = waitingEpic(s, ui.selected);
  const choice = ui.choice;
  if (!waiting?.options || !choice || name === 'escape') return { ui: { ...ui, mode: 'dashboard', choice: undefined } };
  const { names } = waiting.options;
  switch (name) {
    case 'up':
    case 'down':
      return { ui: { ...ui, choice: { ...choice, role: choice.role === 'author' ? 'reviewer' : 'author' } } };
    case 'left':
    case 'right': {
      const at = names.indexOf(choice[choice.role]);
      const next = names[(at + (name === 'right' ? 1 : names.length - 1)) % names.length]!;
      return { ui: { ...ui, choice: { ...choice, [choice.role]: next } } };
    }
    case 'return':
      return { ui: { ...ui, mode: 'dashboard', choice: undefined }, action: { type: 'choose', repo: waiting.repo, issue: waiting.issue, author: choice.author, reviewer: choice.reviewer } };
    default:
      return { ui };
  }
}

/** The state to draw with: a selection that no longer exists moves to the first row, a toast past its time is dropped, logs of nothing go back. */
export function settle(ui: UiState, s: PanelSnapshot, now: number): UiState {
  const items = itemsOf(s);
  const current = items.find((i) => i.key === ui.selected);
  const gone = (ui.mode === 'logs' && !current?.executionId) || (ui.mode === 'choose' && !waitingEpic(s, ui.selected)); // logs of nothing, or an epic that started meanwhile
  return {
    selected: current ? ui.selected : (items[0]?.key ?? null), // something is always selected, so the keys always act on a visible row
    mode: gone ? 'dashboard' : ui.mode,
    ...(ui.mode === 'choose' && !gone && { choice: ui.choice }),
    toast: ui.toast && ui.toast.until > now ? ui.toast : null,
  };
}
