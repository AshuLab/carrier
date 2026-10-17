import { formatDuration } from '../format/duration.ts';
import type { PanelEpic, PanelSnapshot } from './render.ts';

type Style = 'bold' | 'dim' | 'red' | 'green' | 'yellow' | 'cyan';
const codes: Record<Style, number> = { bold: 1, dim: 2, red: 31, green: 32, yellow: 33, cyan: 36 };

// The reason and the error come from the agent's own output: no control character (ESC included) may reach the terminal.
const printable = (text: string) => text.replace(/[\x00-\x1f\x7f-\x9f]/g, ' ');

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
const maxListed = 5;

/**
 * The panel for a terminal: header, slots, then one section per kind of epic (running, queued, needing a person, ready
 * for test). Pure: the same snapshot gives the same lines; `color: false` gives them with no ANSI.
 */
export function renderDashboard(s: PanelSnapshot, { columns = 80, color = true }: { columns?: number; color?: boolean } = {}): string[] {
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
  add();
  const dots = Array.from({ length: s.slots.total }, (_, i) => (i < s.slots.busy ? paint('●', 'green') : paint('○', 'dim'))).join('');
  add(`   Slots  ${dots}   ${s.slots.busy} of ${s.slots.total} busy`);

  const running = s.epics.filter((e) => e.status === 'running');
  const needsYou = s.epics.filter((e) => e.status === 'needs_human');
  const section = (name: string, ...styles: Style[]) => {
    add();
    add(` ${paint(name, 'bold', ...styles)}`);
  };

  const card = (e: PanelEpic, first: boolean) => {
    const bar = paint('┃', 'cyan');
    const chain = e.stage === null ? paint('starting', 'dim') : stages.map((st) => (st === e.stage ? paint(`[${st}]`, 'bold', 'cyan') : paint(st, 'dim'))).join(paint(' ▸ ', 'dim'));
    const round = e.round === null ? '' : ` · round ${Array.from({ length: e.maxReviews }, (_, i) => (i < e.round! ? '●' : '○')).join('')}`;
    if (!first) add();
    add(` ${bar} ${paint(`${e.repo} #${e.issue}`, 'bold')}`);
    add(` ${bar} ${chain}${round}`);
    const blockers = e.blockers > 0 ? paint(` · blockers ${e.blockers}`, 'yellow') : '';
    add(` ${bar} ${formatDuration(s.now - e.stageSince)} in stage · ${e.lastActivityAt === null ? 'no activity yet' : `active ${ago(e.lastActivityAt)}`}${blockers}`);
    add(` ${bar} ${paint(e.prUrl ?? e.issueUrl, 'dim')}`);
    if (e.lastError) add(` ${bar} ${paint(`error: ${printable(e.lastError)}`, 'red')}`);
  };
  if (running.length > 0) {
    section('RUNNING', 'cyan');
    running.forEach((e, i) => card(e, i === 0));
  }

  if (s.queue.length > 0) {
    section(`QUEUED ${s.queue.length}`);
    for (const q of s.queue.slice(0, maxListed)) add(`   ${q.repo} #${q.issue}`);
    if (s.queue.length > maxListed) add(paint(`   … and ${s.queue.length - maxListed} more`, 'dim'));
  }

  if (needsYou.length > 0) {
    section('NEEDS YOU ▲', 'yellow');
    for (const e of needsYou) {
      add(`   ${paint(`${e.repo} #${e.issue}`, 'bold')}`);
      if (e.needsHumanReason) add(`   ${printable(e.needsHumanReason)}`);
      add(`   ${paint(e.prUrl ?? e.issueUrl, 'dim')}`);
      if (e.lastError) add(`   ${paint(`error: ${printable(e.lastError)}`, 'red')}`);
    }
  }

  if (s.done.length > 0) {
    section('READY FOR TEST ✔', 'green');
    for (const d of s.done) add(`   ${d.repo} #${d.issue}${d.prNumber === null ? '' : ` · PR #${d.prNumber}`} · ${ago(d.finishedAt)}`);
  }

  if (s.epics.length === 0 && s.queue.length === 0 && s.done.length === 0) {
    add();
    add(`   ${paint('Idle.', 'bold')} Mark an epic ${paint('solve:epic:ready', 'cyan')} in a watched repo to start one.`);
  }

  add();
  add(`   ${paint('Ctrl+C stops it', 'dim')}`);
  return lines.map((line) => fit(line, width + 2));
}
