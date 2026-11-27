import { formatDuration } from '../../format/duration.ts';
import { printable } from './printable.ts';
import { defaultLabels } from '../../orchestration/github.ts';
import type { PanelEpic, PanelReviewers, PanelSnapshot, UnansweredObservations } from '../../status/types.ts';
import { closedCount, closedKey, finishedSections, itemsOf, maxListed, type UiState } from './ui-state.ts';
import { detailOf, historyLine, type DetailProvider } from './history.ts';

type Style = 'bold' | 'dim' | 'inverse' | 'red' | 'green' | 'yellow' | 'cyan';
const codes: Record<Style, number> = { bold: 1, dim: 2, inverse: 7, red: 31, green: 32, yellow: 33, cyan: 36 };

/** Whether the panel paints at all: not with `NO_COLOR` set to anything (no-color.org) nor on a `dumb` terminal. A caller that draws to a terminal asks this; the render itself takes `color` as it is given. */
export const colorWanted = (env: Record<string, string | undefined> = process.env) => (env.NO_COLOR ?? '') === '' && env.TERM !== 'dumb';

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

/** What an epic that went to ready for test with observations nobody answered says: how many and why, short enough to show whole at 50 columns. */
export const unansweredLine = ({ count, reason }: UnansweredObservations) =>
  `${count} unanswered observation${count === 1 ? '' : 's'}: ${reason === 'already_taken' ? 'pass already taken' : 'last round'}`;

/** How many reviewers of the latest round gave a verdict out of how many were configured: "1 of 3 gave a verdict". */
export const reviewersLine = ({ given, of }: Pick<PanelReviewers, 'given' | 'of'>) => `${given} of ${of} gave a verdict`;

/** How long a running agent may write nothing before its card says so (yellow), and before it says it louder (red). */
export const quietAfterMs = 5 * 60_000;
export const stuckAfterMs = 15 * 60_000;

const stages = ['ship', 'review', 'fix'] as const;
/** The stage lead is `review` with `lead` set in the snapshot (the app's stage is a strict enum): the chain draws it as a stage of its own, after the others. */
const chainOf = (e: Pick<PanelEpic, 'stage' | 'lead'>) => (e.lead ? [...stages, 'lead' as const] : stages);
const activeOf = (e: Pick<PanelEpic, 'stage' | 'lead'>) => (e.lead ? 'lead' : e.stage);

export type DashboardOptions = {
  columns?: number;
  /** The height of the terminal. Given, the lines never reach it (the last row stays free): the middle scrolls to keep the selected row in view. Absent, nothing is cut. */
  rows?: number;
  color?: boolean;
  /** Present when the panel takes keys: the selection, the screen and the toast. Absent: a plain, read-only dashboard. */
  ui?: UiState;
  /** The program can dismiss a closed epic: the key `d` is offered (and listed) for a closed row. */
  dismiss?: boolean;
  /** The program can resume a stopped epic: the key `r` is offered (and listed) for a NEEDS YOU row. */
  resume?: boolean;
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
 * for test, closed). Pure: the same snapshot gives the same lines; `color: false` gives them with no ANSI.
 * With `ui` (the panel takes keys) an unselected running card is two lines and the closed epics are one section that starts folded;
 * without it (`carrier status`, a pipe) every card is whole and the closed ones are listed.
 */
export function renderDashboard(s: PanelSnapshot, { columns = 80, rows, color = true, ui, dismiss = false, resume = false, logLines = [], activity, detail, quit = 'stop' }: DashboardOptions = {}): string[] {
  const paint = (text: string, ...styles: Style[]) => (color && styles.length > 0 ? `\x1b[${styles.map((x) => codes[x]).join(';')}m${text}\x1b[0m` : text);
  const width = Math.min(Math.max(columns, 50), 80) - 2;
  const ago = (at: number | null) => (at === null ? 'a while' : `${formatDuration(Math.max(0, s.now - at))} ago`);

  const running = s.epics.filter((e) => e.status === 'running');
  const needsYou = s.epics.filter((e) => e.status === 'needs_human');
  const closedOpen = ui?.closedOpen ?? false;

  const up = `up ${formatDuration(s.now - s.startedAt)}`;
  const title = '◆ CARRIER ';
  const rule = '─'.repeat(Math.max(3, width - title.length - up.length - 2));
  const lines: string[] = [];
  const add = (text = '') => lines.push(text);
  // The lines of the selected row inside `lines`, so a screen taller than the terminal can keep it in view.
  let marked: [number, number] | null = null;
  // Where each row starts, so a window cut by the terminal's height begins and ends between rows, not inside one.
  const starts: number[] = [];
  const breaks: number[] = []; // and each section, so a heading is not left alone at the foot
  const mark = (chosen: boolean, draw: () => void) => {
    const from = lines.length;
    starts.push(from);
    draw();
    if (chosen) marked = [from, lines.length - 1];
  };

  add(` ${paint(title, 'bold', 'cyan')}${paint(rule, 'dim')} ${paint(up, 'dim')}`);
  const wait = s.nextCheckAt === null ? 'starting' : s.nextCheckAt <= s.now ? 'checking now…' : `next check in ${formatDuration(s.nextCheckAt - s.now)}`;
  add(`   ${paint(`watching ${s.repos} repo${s.repos === 1 ? '' : 's'} · ${wait}`, 'dim')}`);
  // What there is at a glance, so what needs a person shows even when the list below runs past the screen.
  const summary = [
    running.length > 0 && `${running.length} running`,
    s.queue.length > 0 && `${s.queue.length} queued`,
    needsYou.length > 0 && paint(`▲ ${needsYou.length} needs you`, 'yellow'),
    s.done.length > 0 && paint(`✔ ${s.done.length} ready`, 'green'),
  ].filter(Boolean) as string[];
  if (summary.length > 0) add(`   ${summary.join(paint(' · ', 'dim'))}`);
  if (s.problem) add(`   ${paint(`▲ ${printable(s.problem)}`, 'yellow')}`);
  if (s.paused) add(`   ${paint('▲ PAUSED: new epics wait in the queue (p to unpause)', 'yellow')}`);
  add();
  const dots = Array.from({ length: s.slots.total }, (_, i) => (i < s.slots.busy ? paint('●', 'green') : paint('○', 'dim'))).join('');
  add(`   Slots  ${dots}   ${s.slots.busy} of ${s.slots.total} busy`);
  const headEnd = lines.length;

  const section = (name: string, ...styles: Style[]) => {
    breaks.push(lines.length);
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
  // Packed into as many lines as the width needs: a line cut at the edge loses the keys at its end (q among them).
  const hints = () => {
    const items = itemsOf(s, closedOpen);
    const current = items.find((i) => i.key === ui?.selected);
    const parts = [items.length > 1 && '↑↓ select', current && (current.header ? (closedOpen ? 'enter fold' : 'enter open closed') : 'enter open'), current?.executionId && 'l logs', resume && current?.stopped && (ui?.confirm === current.key ? 'r confirm' : 'r resume'), dismiss && current?.closed && 'd dismiss', closedCount(s) > 0 && !current?.header && (closedOpen ? 'f hide closed' : 'f show closed'), 'c check now', s.paused ? 'p unpause' : 'p pause', '? help', quit === 'stop' ? 'q quit' : 'q leave'].filter(Boolean) as string[];
    return parts.reduce<string[]>((rows, part) => {
      const last = rows.at(-1);
      if (last !== undefined && visibleLength(`${last} · ${part}`) <= width - 1) rows[rows.length - 1] = `${last} · ${part}`;
      else rows.push(part);
      return rows;
    }, []);
  };
  const footer = () => {
    // With keys the foot is a status bar: a rule that closes the list, what just happened (no `›`: that is the selection's), then the keys.
    const foot: string[] = [ui === undefined ? '' : ` ${paint('─'.repeat(width - 1), 'dim')}`];
    // A resume that waits for its second R says what it will do, and stays until answered or withdrawn: it is not a toast that fades.
    const asked = ui?.confirm === undefined ? undefined : itemsOf(s, closedOpen).find((i) => i.key === ui.confirm);
    if (asked) {
      foot.push(`   ${paint(`Resume ${printable(asked.key)}? It starts again from ship, on the same agents.`, 'yellow')}`);
      if (asked.usage) foot.push(`   ${paint('It ran out of usage: carrier restart lets you pick another agent.', 'yellow')}`);
      foot.push(`   ${paint('r confirms · any other key cancels', 'yellow')}`);
    } else if (ui?.toast) foot.push(`   ${paint(printable(ui.toast.text), 'cyan')}`);
    const exit = quit === 'stop' ? 'q quit' : 'q leave';
    const keys = ui === undefined ? [quit === 'stop' ? 'Ctrl+C stops it' : 'Ctrl+C leaves it running'] : ui.mode === 'dashboard' ? hints() : [`esc back · ${exit}`];
    for (const row of keys) foot.push(`   ${paint(row, 'dim')}`);
    return foot;
  };

  /**
   * `lines` as the screen shows them: the first `headEnd` stay, then a window of the rest, then the footer.
   * Too tall for `rows`, the window keeps `focus` (the selected row's lines, or the end for the logs) in view and says what hides above and below.
   */
  const screen = (focus: [number, number] | 'end' | null, pinned: number) => {
    const foot = footer();
    const top = lines.slice(0, pinned);
    const body = lines.slice(pinned);
    const available = rows === undefined ? Infinity : Math.max(3, rows - 1 - top.length - foot.length); // below about twelve rows the screen gives up the last row before the window
    if (body.length <= available) return [...top, ...body, ...foot].map((line) => fit(line, width + 2));
    const [first, last] = focus === 'end' ? [body.length - 1, body.length - 1] : (focus ?? [pinned, pinned]).map((i) => i - pinned);
    // How many body lines fit when the window starts at `start`: one less for each "more" line it needs.
    const room = (start: number) => {
      const withoutBottom = available - (start > 0 ? 1 : 0);
      return start + withoutBottom >= body.length ? withoutBottom : withoutBottom - 1;
    };
    let start = 0;
    while (start + room(start) <= last! && start < body.length - 1) start += 1;
    start = Math.min(start, first!); // a row taller than the window shows from its top
    const rowStarts = starts.map((i) => i - pinned);
    if (start > 0) start = rowStarts.find((i) => i >= start && i <= first!) ?? start; // begin on a row
    let end = start + room(start);
    if (end < body.length) {
      // and end between rows, never inside one nor right after a heading
      const headed = breaks.map((i) => i - pinned + 2);
      end = [...rowStarts.filter((i) => !headed.includes(i)), ...breaks.map((i) => i - pinned)].filter((i) => i > last! && i <= end).sort((a, b) => a - b).at(-1) ?? end;
    }
    const shown = body.slice(start, end);
    while (shown.length > 1 && shown.at(-1) === '') shown.pop();
    const below = body.length - (start + shown.length);
    return [
      ...top,
      ...(start > 0 ? [`   ${paint(`↑ ${start} more lines`, 'dim')}`] : []),
      ...shown,
      ...(below > 0 ? [`   ${paint(`↓ ${below} more lines`, 'dim')}`] : []),
      ...foot,
    ].map((line) => fit(line, width + 2));
  };

  if (ui?.mode === 'help') {
    lines.length = 0;
    section('KEYS');
    const keys = [['↑ ↓ j k', 'select an epic'], ['enter', 'open its PR (or issue) in the browser'], ['l', 'agent output of the selected epic'], ['c', 'check GitHub now'], ['p', 'pause or unpause taking new epics'], ['f', 'show or hide the closed epics (merged, cancelled)'], ['← →', 'fold or open CLOSED when selected (enter does too)'], ...(dismiss ? [['d', 'dismiss the selected closed epic: hide it for good']] : []), ...(resume ? [['r', 'resume the selected stopped epic (asks first; same agents, from ship)']] : []), ['?', 'this help'], ['esc', 'back'], ['q', quit === 'stop' ? 'stop Carrier (same as Ctrl+C)' : 'leave (Carrier keeps running)']];
    for (const [key, what] of keys) add(`   ${paint(key!.padEnd(9), 'bold', 'cyan')} ${what}`);
    return screen(null, 0);
  }
  if (ui?.mode === 'logs') {
    lines.length = 0;
    const target = [...s.epics, ...s.done, ...(s.finished ?? [])].find((e) => selected(e.repo, e.issue));
    section(`AGENT OUTPUT · ${ui.selected ?? ''}${target?.executionId ? ` · ${target.executionId.slice(0, 8)}` : ''}`, 'cyan');
    if (logLines.length === 0) add(paint('   (nothing written yet)', 'dim'));
    for (const l of logLines) add(`   ${printable(l)}`);
    return screen('end', 2); // the title stays, the end of the output is what is read
  }

  // The count of the latest round and, in yellow, why each reviewer without a verdict gave none (an agent wrote it: printable, and `fit` cuts the line).
  const reviewerLines = (reviewers: PanelReviewers | undefined) => (reviewers ? [`reviewers ${reviewersLine(reviewers)}`, ...reviewers.none.map((n) => paint(`  · ${n.slot}: ${printable(n.why)}`, 'yellow'))] : []);
  const card = (e: PanelEpic, first: boolean) => {
    const chosen = selected(e.repo, e.issue);
    const compact = ui !== undefined && !chosen; // with keys, only the selected card shows everything
    const bar = chosen ? paint('▌', 'bold', 'cyan') : paint('┃', 'dim');
    const stage = e.stage === null ? paint('starting', 'dim') : paint(`[${activeOf(e)}]`, 'bold', 'cyan');
    const chain = e.stage === null ? paint('starting', 'dim') : chainOf(e).map((st) => (st === activeOf(e) ? paint(`[${st}]`, 'bold', 'cyan') : paint(st, 'dim'))).join(paint(' ▸ ', 'dim'));
    const dots = (gap: string) => (e.round === null ? '' : ` · round ${Array.from({ length: e.maxReviews }, (_, i) => (i < e.round! ? '●' : '○')).join(gap)}`);
    const round = dots(' ');
    const blockers = e.blockers > 0 ? paint(` · blockers ${e.blockers}`, 'yellow') : '';
    const slices = e.slices && e.slices.total > 0 ? ` · slices ${e.slices.done}/${e.slices.total}` : '';
    const inStage = `${formatDuration(s.now - e.stageSince)} in stage`;
    // A running agent that has written nothing for a while is the one to look at: yellow, then red, and a ▲ so it shows without color too.
    // An epic waiting out a retry is quiet on purpose.
    const quiet = e.retryAt === undefined ? s.now - (e.lastActivityAt ?? e.stageSince) : 0;
    const activeText = e.lastActivityAt === null ? 'no activity yet' : `active ${ago(e.lastActivityAt)}`;
    const active = quiet >= stuckAfterMs ? paint(`${activeText} ▲`, 'red') : quiet >= quietAfterMs ? paint(`${activeText} ▲`, 'yellow') : activeText;
    if (!first) add();
    mark(chosen, () => {
      add(chosen ? ` ${pointer}${paint(` ${e.repo} #${e.issue} `, 'bold', 'inverse')}${titled(e.title)}` : ` ${bar} ${paint(`${e.repo} #${e.issue}`, 'bold')}${titled(e.title)}`); // the selected card's title is a highlighted label
      if (compact) {
        // What a glance needs first, the times last: a cut line loses them, not the blockers. Just the stage it is in; the whole chain is on the selected card.
        const glance = (r: string) => ` ${bar} ${stage}${r}${blockers}${slices} · ${formatDuration(s.now - e.stageSince)} · ${active}`;
        // The dots keep their spaces unless that cuts the times off the end of the line: then they close up.
        add(visibleLength(glance(round)) <= width + 2 ? glance(round) : glance(dots('')));
      } else {
        add(` ${bar} ${chain}${round}`);
        const history = detail && detailOf(detail, e);
        if (history && history.length > 0) add(` ${bar} ${historyLine(history, s.now, paint, width - 4)}`);
        add(` ${bar} ${inStage} · ${active}${blockers}${slices}`);
        for (const text of reviewerLines(e.reviewers)) add(` ${bar} ${text}`);
        add(` ${bar} ${paint(e.prUrl ?? e.issueUrl, 'dim')}`);
      }
      if (e.retryAt !== undefined) add(` ${bar} ${e.retryAt > s.now ? `retrying in ${formatDuration(e.retryAt - s.now)}` : 'retrying at the next check'}`);
      if (e.lastError) add(` ${bar} ${paint(`error: ${printable(e.lastError)}`, 'red')}`);
      if (compact) return;
      // What the agent is doing: three lines for the selected card, one for the others (read-only, no selection).
      const now = e.executionId && activity ? activity(e.executionId, chosen ? 3 : 1) : [];
      now.forEach((l, i) => add(` ${bar} ${i === 0 ? paint('now', 'dim') : '   '}  ${paint(printable(l), 'dim')}`));
      // The open blockers of a review or fix, by title, listed the way the queue is.
      const titles = e.stage === 'review' || e.stage === 'fix' ? (e.blockerTitles ?? []) : [];
      for (const t of titles.slice(0, 3)) add(` ${bar}   ${paint(`· ${printable(t)}`, 'yellow')}`);
      if (titles.length > 0 && e.blockers > 3) add(` ${bar}   ${paint(`… and ${e.blockers - 3} more`, 'dim')}`);
    });
  };
  if (running.length > 0) {
    section('RUNNING', 'cyan');
    running.forEach((e, i) => card(e, i === 0));
  }

  if (s.queue.length > 0) {
    section(`QUEUED ${s.queue.length}`);
    for (const q of s.queue.slice(0, maxListed)) mark(selected(q.repo, q.issue), () => add(`${lead(q.repo, q.issue, '   ')}${q.repo} #${q.issue}${titled(q.title)}`));
    if (s.queue.length > maxListed) add(paint(`   … and ${s.queue.length - maxListed} more`, 'dim'));
  }

  if (needsYou.length > 0) {
    section('NEEDS YOU ▲', 'yellow');
    for (const e of needsYou) {
      mark(selected(e.repo, e.issue), () => {
        add(`${lead(e.repo, e.issue, '   ')}${paint(`${e.repo} #${e.issue}`, 'bold')}${titled(e.title)}`);
        if (e.needsHumanReason) add(`   ${printable(e.needsHumanReason)}`);
        for (const text of reviewerLines(e.reviewers)) add(`   ${text}`);
        if (e.resumeAt !== undefined) add(`   ${e.resumeAt > s.now ? `resumes by itself in ${formatDuration(e.resumeAt - s.now)}` : 'resumes by itself at the next check'}`);
        const history = detail && detailOf(detail, e);
        if (history && history.length > 0) add(`   ${historyLine(history, s.now, paint, width - 3)}`);
        add(`   ${paint(e.prUrl ?? e.issueUrl, 'dim')}`);
        if (e.lastError) add(`   ${paint(`error: ${printable(e.lastError)}`, 'red')}`);
      });
    }
  }

  // last: a cut title costs less than a cut PR number or time
  const row = (d: { repo: string; issue: number; title: string | null; prNumber: number | null; finishedAt: number | null }) =>
    `${lead(d.repo, d.issue, '   ')}${d.repo} #${d.issue}${d.prNumber === null ? '' : ` · PR #${d.prNumber}`} · ${ago(d.finishedAt)}${titled(d.title)}`;

  if (s.done.length > 0) {
    section('READY FOR TEST ✔', 'green');
    for (const d of s.done) {
      mark(selected(d.repo, d.issue), () => {
        add(row(d));
        if (d.unansweredObservations) add(`   ${paint(unansweredLine(d.unansweredObservations), 'yellow')}`);
        for (const text of reviewerLines(d.reviewers)) add(`   ${text}`);
        const history = detail && detailOf(detail, d);
        if (history && history.length > 0) add(`   ${historyLine(history, s.now, paint, width - 3)}`);
      });
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
    add(s.repos === 0 ? `   ${paint('Idle.', 'bold')} No repos are watched yet: add one to the config's ${paint('repos', 'cyan')}.` : `   ${paint('Idle.', 'bold')} Mark an epic ${paint((s.labels ?? defaultLabels).ready, 'cyan')} in a watched repo to start one.`);
  }

  // The epics that ended: with keys they are one section that starts folded (they are done, and the live ones matter more); read-only they are listed.
  const closed = closedCount(s);
  if (ui !== undefined && closed > 0) {
    // A row like the others: the arrows reach it, and enter (or → and ←) opens and folds what is under it.
    const label = `CLOSED ${closed} ${closedOpen ? '▾' : '▸'}`;
    breaks.push(lines.length);
    add();
    mark(ui.selected === closedKey, () => add(ui.selected === closedKey ? ` ${pointer}${paint(` ${label} `, 'bold', 'inverse')}` : ` ${paint(label, 'bold', 'dim')}`));
  }
  if (ui === undefined || closedOpen) {
    for (const { name, rows: listed, more } of finishedSections(s)) {
      if (ui === undefined) section(name, 'dim');
      else add(`   ${paint(name, 'bold', 'dim')}`);
      for (const f of listed) {
        mark(selected(f.repo, f.issue), () => {
          add(row(f));
          if (f.cancelReason) add(`   ${printable(f.cancelReason)}`);
        });
      }
      if (more > 0) add(paint(`   +${more} more`, 'dim'));
    }
  }

  return screen(marked, headEnd);
}
