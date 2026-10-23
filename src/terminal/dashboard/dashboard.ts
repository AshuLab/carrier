import { formatDuration } from '../../format/duration.ts';
import { printable } from './printable.ts';
import type { PanelEpic, PanelSnapshot } from '../../status/types.ts';
import { finishedSections, itemsOf, maxListed, type UiState } from './ui-state.ts';
import { detailOf, historyLine, type DetailProvider } from './history.ts';

type Style = 'bold' | 'dim' | 'inverse' | 'red' | 'green' | 'yellow' | 'cyan';
const codes: Record<Style, number> = { bold: 1, dim: 2, inverse: 7, red: 31, green: 32, yellow: 33, cyan: 36 };

// eslint-disable-next-line no-control-regex
const ansi = /\x1b\[[0-9;]*m/g;
export const visibleLength = (text: string) => text.replace(ansi, '').length;

/** Cuts a styled line to `columns` visible characters (a wrapped line would break the cursor-up count of the redraw). */
export function fit(line: string, columns: number): string {
  if (visibleLength(line) <= columns) return line;
  let out = '';
  let shown = 0;
  let open = false; // a style is on and not yet reset
  for (const part of line.split(/(\x1b\[[0-9;]*m)/)) {
    if (/^\x1b\[[0-9;]*m$/.test(part)) {
      out += part;
      open = part !== '\x1b[0m';
    } else {
      const room = columns - shown;
      out += part.slice(0, Math.max(0, room));
      shown += Math.min(part.length, Math.max(0, room));
    }
  }
  return open ? `${out}\x1b[0m` : out;
}

const stages = ['ship', 'review', 'fix'] as const;

export type DashboardOptions = {
  columns?: number;
  color?: boolean;
  /** Present when the panel takes keys: the selection, the screen and the toast. Absent: a plain, read-only dashboard. */
  ui?: UiState;
  /** The agent output shown in the logs screen. */
  logLines?: string[];
  /** The last lines an execution's agent wrote: what a running card shows as "now". */
  activity?: (executionId: string, count: number) => string[];
  /** How each stage of an epic went; without it, or when it knows nothing of the epic, the card has no stages line. */
  detail?: DetailProvider;
  /** What `q` and Ctrl+C do: 'stop' Carrier (the foreground, the default) or 'leave' it running (`watch`). */
  quit?: 'stop' | 'leave';
};

/**
 * The panel for a terminal: header, slots, then one section per kind of epic (running, queued, needing a person, ready
 * for test). Pure: the same snapshot gives the same lines; `color: false` gives them with no ANSI.
 */
export function renderDashboard(s: PanelSnapshot, { columns = 80, color = true, ui, logLines = [], activity, detail, quit = 'stop' }: DashboardOptions = {}): string[] {
  const paint = (text: string, ...styles: Style[]) => (color && styles.length > 0 ? `\x1b[${styles.map((x) => codes[x]).join(';')}m${text}\x1b[0m` : text);
  const width = Math.min(Math.max(columns, 50), 80) - 2;
  const ago = (at: number | null) => (at === null ? 'a while' : `${formatDuration(Math.max(0, s.now - at))} ago`);

  const up = `up ${formatDuration(s.now - s.startedAt)}`;
  const title = '◆ CARRIER ';
  const rule = '─'.repeat(Math.max(3, width - title.length - up.length - 2));
  const lines: string[] = [];
  const add = (text = '') => lines.push(text);

  add(` ${paint(title, 'bold', 'cyan')}${paint(rule, 'dim')} ${paint(up, 'dim')}`);
  const wait = s.nextCheckAt === null ? 'starting' : s.nextCheckAt <= s.now ? 'checking now…' : `next check in ${formatDuration(s.nextCheckAt - s.now)}`;
  add(`   ${paint(`watching ${s.repos} repo${s.repos === 1 ? '' : 's'} · ${wait}`, 'dim')}`);
  if (s.problem) add(`   ${paint(`▲ ${printable(s.problem)}`, 'yellow')}`);
  if (s.paused) add(`   ${paint('▲ PAUSED: new epics wait in the queue (p resumes)', 'yellow')}`);
  add();
  const dots = Array.from({ length: s.slots.total }, (_, i) => (i < s.slots.busy ? paint('●', 'green') : paint('○', 'dim'))).join('');
  add(`   Slots  ${dots}   ${s.slots.busy} of ${s.slots.total} busy`);

  const section = (name: string, ...styles: Style[]) => {
    add();
    add(` ${paint(name, 'bold', ...styles)}`);
  };
  const selected = (repo: string, issue: number) => ui?.selected === `${repo}#${issue}`;
  // An issue title is written by someone else: printable, and `fit` cuts the line. A missing one leaves the row as it was.
  const titled = (title: string | null | undefined) => (title ? `  ${printable(title)}` : '');
  const pointer = paint('›', 'bold', 'cyan');
  // The first line of the selected row carries the pointer where the others have the bar or the indent.
  const lead = (repo: string, issue: number, plain: string) => (selected(repo, issue) ? ` ${pointer} ` : plain);

  // Only the keys that do something now: no ↑↓ with one row, no logs for a row with no agent.
  const hints = () => {
    const items = itemsOf(s);
    const current = items.find((i) => i.key === ui?.selected);
    return [items.length > 1 && '↑↓ select', current && 'enter open', current?.executionId && 'l logs', 'r check now', s.paused ? 'p resume' : 'p pause', '? help', quit === 'stop' ? 'q quit' : 'q leave'].filter(Boolean).join(' · ');
  };
  const footer = () => {
    if (ui?.toast) add(`   ${paint(`› ${printable(ui.toast.text)}`, 'cyan')}`);
    add();
    add(`   ${paint(ui === undefined ? (quit === 'stop' ? 'Ctrl+C stops it' : 'Ctrl+C leaves it running') : ui.mode === 'dashboard' ? hints() : `esc back · ${quit === 'stop' ? 'q quit' : 'q leave'}`, 'dim')}`);
  };

  if (ui?.mode === 'help') {
    section('KEYS');
    for (const [key, what] of [['↑ ↓ j k', 'select an epic'], ['enter', 'open its PR (or issue) in the browser'], ['l', 'agent output of the selected epic'], ['r', 'check GitHub now'], ['p', 'pause or resume taking new epics'], ['?', 'this help'], ['esc', 'back'], ['q', quit === 'stop' ? 'stop Carrier (same as Ctrl+C)' : 'leave (Carrier keeps running)']]) add(`   ${paint(key!.padEnd(9), 'bold', 'cyan')} ${what}`);
    footer();
    return lines.map((line) => fit(line, width + 2));
  }
  if (ui?.mode === 'logs') {
    const target = [...s.epics, ...s.done, ...(s.finished ?? [])].find((e) => selected(e.repo, e.issue));
    section(`AGENT OUTPUT · ${ui.selected ?? ''}${target?.executionId ? ` · ${target.executionId.slice(0, 8)}` : ''}`, 'cyan');
    if (logLines.length === 0) add(paint('   (nothing written yet)', 'dim'));
    for (const l of logLines) add(`   ${printable(l)}`);
    footer();
    return lines.map((line) => fit(line, width + 2));
  }

  const running = s.epics.filter((e) => e.status === 'running');
  const needsYou = s.epics.filter((e) => e.status === 'needs_human');

  const card = (e: PanelEpic, first: boolean) => {
    const chosen = selected(e.repo, e.issue);
    const bar = chosen ? paint('▌', 'bold', 'cyan') : paint('┃', 'dim');
    const chain = e.stage === null ? paint('starting', 'dim') : stages.map((st) => (st === e.stage ? paint(`[${st}]`, 'bold', 'cyan') : paint(st, 'dim'))).join(paint(' ▸ ', 'dim'));
    const round = e.round === null ? '' : ` · round ${Array.from({ length: e.maxReviews }, (_, i) => (i < e.round! ? '●' : '○')).join('')}`;
    if (!first) add();
    add(chosen ? ` ${pointer}${paint(` ${e.repo} #${e.issue} `, 'bold', 'inverse')}${titled(e.title)}` : ` ${bar} ${paint(`${e.repo} #${e.issue}`, 'bold')}${titled(e.title)}`); // the selected card's title is a highlighted label
    add(` ${bar} ${chain}${round}`);
    const history = detail && detailOf(detail, e);
    if (history && history.length > 0) add(` ${bar} ${historyLine(history, s.now, paint, width - 4)}`);
    const blockers = e.blockers > 0 ? paint(` · blockers ${e.blockers}`, 'yellow') : '';
    const slices = e.slices && e.slices.total > 0 ? ` · slices ${e.slices.done}/${e.slices.total}` : '';
    add(` ${bar} ${formatDuration(s.now - e.stageSince)} in stage · ${e.lastActivityAt === null ? 'no activity yet' : `active ${ago(e.lastActivityAt)}`}${blockers}${slices}`);
    add(` ${bar} ${paint(e.prUrl ?? e.issueUrl, 'dim')}`);
    if (e.lastError) add(` ${bar} ${paint(`error: ${printable(e.lastError)}`, 'red')}`);
    // What the agent is doing: three lines for the selected card, one for the others.
    const now = e.executionId && activity ? activity(e.executionId, chosen ? 3 : 1) : [];
    now.forEach((l, i) => add(` ${bar} ${i === 0 ? paint('now', 'dim') : '   '}  ${paint(printable(l), 'dim')}`));
    // The open blockers of a review or fix, by title, listed the way the queue is.
    const titles = e.stage === 'review' || e.stage === 'fix' ? (e.blockerTitles ?? []) : [];
    for (const t of titles.slice(0, 3)) add(` ${bar}   ${paint(`· ${printable(t)}`, 'yellow')}`);
    if (titles.length > 0 && e.blockers > 3) add(` ${bar}   ${paint(`… and ${e.blockers - 3} more`, 'dim')}`);
  };
  if (running.length > 0) {
    section('RUNNING', 'cyan');
    running.forEach((e, i) => card(e, i === 0));
  }

  if (s.queue.length > 0) {
    section(`QUEUED ${s.queue.length}`);
    for (const q of s.queue.slice(0, maxListed)) add(`${lead(q.repo, q.issue, '   ')}${q.repo} #${q.issue}${titled(q.title)}`);
    if (s.queue.length > maxListed) add(paint(`   … and ${s.queue.length - maxListed} more`, 'dim'));
  }

  if (needsYou.length > 0) {
    section('NEEDS YOU ▲', 'yellow');
    for (const e of needsYou) {
      add(`${lead(e.repo, e.issue, '   ')}${paint(`${e.repo} #${e.issue}`, 'bold')}${titled(e.title)}`);
      if (e.needsHumanReason) add(`   ${printable(e.needsHumanReason)}`);
      const history = detail && detailOf(detail, e);
      if (history && history.length > 0) add(`   ${historyLine(history, s.now, paint, width - 3)}`);
      add(`   ${paint(e.prUrl ?? e.issueUrl, 'dim')}`);
      if (e.lastError) add(`   ${paint(`error: ${printable(e.lastError)}`, 'red')}`);
    }
  }

  // last: a cut title costs less than a cut PR number or time
  const row = (d: { repo: string; issue: number; title: string | null; prNumber: number | null; finishedAt: number | null }) =>
    `${lead(d.repo, d.issue, '   ')}${d.repo} #${d.issue}${d.prNumber === null ? '' : ` · PR #${d.prNumber}`} · ${ago(d.finishedAt)}${titled(d.title)}`;

  if (s.done.length > 0) {
    section('READY FOR TEST ✔', 'green');
    for (const d of s.done) {
      add(row(d));
      const history = detail && detailOf(detail, d);
      if (history && history.length > 0) add(`   ${historyLine(history, s.now, paint, width - 3)}`);
    }
  }

  // Only while GitHub refused some repo's last check; a healthy Carrier shows nothing extra.
  const refused = (s.watched ?? []).filter((w) => !w.ok);
  if (refused.length > 0) {
    section('REPOS GITHUB REFUSED ▲', 'yellow');
    for (const w of refused) add(`   ${paint(w.repo, 'bold')}  ${paint(printable(w.error ?? 'the last check failed'), 'red')}`);
  }

  if (s.epics.length === 0 && s.queue.length === 0 && s.done.length === 0) {
    add();
    add(`   ${paint('Idle.', 'bold')} Mark an epic ${paint('solve:epic:ready', 'cyan')} in a watched repo to start one.`);
  }

  for (const { name, rows, more } of finishedSections(s)) {
    section(name, 'dim');
    for (const f of rows) {
      add(row(f));
      if (f.cancelReason) add(`   ${printable(f.cancelReason)}`);
    }
    if (more > 0) add(paint(`   +${more} more`, 'dim'));
  }

  footer();
  return lines.map((line) => fit(line, width + 2));
}
