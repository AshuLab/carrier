import { expect, test } from 'vitest';
import { fit, renderDashboard, visibleLength } from './dashboard.ts';
import type { PanelEpic, PanelSnapshot } from '../../status/types.ts';

const now = 10 * 3_600_000;
const epic = (over: Partial<PanelEpic> = {}): PanelEpic => ({
  repo: 'AshuLab/carrier',
  issue: 31,
  status: 'running',
  stage: 'ship',
  round: null,
  maxReviews: 5,
  blockers: 0,
  stageSince: now - 760_000,
  lastActivityAt: now - 8_000,
  issueUrl: 'https://github.com/AshuLab/carrier/issues/31',
  prUrl: null,
  lastError: null,
  needsHumanReason: null,
  slices: null,
  executionId: null,
  ...over,
});
const snap = (over: Partial<PanelSnapshot> = {}): PanelSnapshot => ({
  now,
  slots: { busy: 0, total: 3 },
  queue: [],
  epics: [],
  startedAt: now - (2 * 3600 + 14 * 60) * 1000,
  repos: 2,
  nextCheckAt: now + 192_000,
  problem: null,
  paused: false,
  done: [],
  ...over,
});
const plain = (s: PanelSnapshot, columns = 80) => renderDashboard(s, { columns, color: false }).join('\n');

test('idle: it says what it is doing and what to do, instead of a bare header', () => {
  expect(plain(snap())).toMatchInlineSnapshot(`
    " ◆ CARRIER ───────────────────────────────────────────────────────── up 2h 14m
       watching 2 repos · next check in 3m 12s

       Slots  ○○○   0 of 3 busy

       Idle. Mark an epic solve:epic:ready in a watched repo to start one.

       Ctrl+C stops it"
  `);
});

test('a running epic shows its stage in the chain, rounds as dots, blockers, times and the PR link', () => {
  const out = plain(snap({ slots: { busy: 2, total: 3 }, epics: [epic(), epic({ repo: 'AshuLab/api', issue: 7, stage: 'review', round: 2, blockers: 1, prUrl: 'https://github.com/AshuLab/api/pull/9', stageSince: now - 182_000, lastActivityAt: now - 21_000 })] }));
  expect(out).toContain('Slots  ●●○   2 of 3 busy');
  expect(out).toContain('RUNNING');
  expect(out).toContain('┃ AshuLab/carrier #31\n ┃ [ship] ▸ review ▸ fix\n ┃ 12m 40s in stage · active 8s ago\n ┃ https://github.com/AshuLab/carrier/issues/31');
  expect(out).toContain('┃ ship ▸ [review] ▸ fix · round ●●○○○');
  expect(out).toContain('3m 02s in stage · active 21s ago · blockers 1');
  expect(out).toContain('┃ https://github.com/AshuLab/api/pull/9'); // the PR once there is one
});

test('a running epic shows its slices closed out of the total, and nothing when unknown or without sub-issues', () => {
  expect(plain(snap({ epics: [epic({ slices: { done: 3, total: 5 } })] }))).toContain('in stage · active 8s ago · slices 3/5');
  expect(plain(snap({ epics: [epic({ blockers: 1, slices: { done: 0, total: 2 } })] }))).toContain(' · blockers 1 · slices 0/2');
  expect(plain(snap({ epics: [epic()] }))).not.toContain('slices');
  expect(plain(snap({ epics: [epic({ slices: { done: 0, total: 0 } })] }))).not.toContain('slices');
});

test('queue, needs you, ready for test, and a problem banner', () => {
  const out = plain(
    snap({
      queue: Array.from({ length: 7 }, (_, i) => ({ repo: 'AshuLab/web', issue: 30 + i })),
      epics: [epic({ issue: 29, status: 'needs_human', needsHumanReason: 'inconclusive review: missing context' })],
      done: [{ repo: 'AshuLab/carrier', issue: 28, title: 'Menu bar', labels: [], prNumber: 44, finishedAt: now - 7_200_000, executionId: null }],
      problem: 'GitHub is unavailable: it will be tried again',
    }),
  );
  expect(out).toContain('▲ GitHub is unavailable: it will be tried again');
  expect(out).toContain('QUEUED 7\n   AshuLab/web #30');
  expect(out).toContain('… and 2 more');
  expect(out).toContain('NEEDS YOU ▲\n   AshuLab/carrier #29\n   inconclusive review: missing context');
  expect(out).toContain('READY FOR TEST ✔\n   AshuLab/carrier #28 · PR #44 · 2h 00m ago  Menu bar');
  expect(out).not.toContain('Idle.');
});

test('the wait for the next poll reads right before, during and after it is due', () => {
  expect(plain(snap({ nextCheckAt: null }))).toContain('watching 2 repos · starting');
  expect(plain(snap({ nextCheckAt: now - 1 }))).toContain('watching 2 repos · checking now…');
  expect(plain(snap({ repos: 1 }))).toContain('watching 1 repo ·');
});

test('what an agent wrote never reaches the terminal as a control sequence', () => {
  const out = plain(snap({ epics: [epic({ status: 'needs_human', needsHumanReason: 'a\x1b[2Jb', lastError: 'c\r\nd\x07' }), epic({ lastError: 'x\x1b[0my' })] }));
  expect(out).not.toMatch(/[\x07\x1b\r]/);
  expect(out).toContain('a [2Jb');
});

test('every kind of row shows the epic title when it has one, and reads as before when it has none', () => {
  const titled = snap({
    queue: [{ repo: 'AshuLab/web', issue: 30, title: 'Queued thing' }, { repo: 'AshuLab/web', issue: 31, title: null }, { repo: 'AshuLab/web', issue: 32 }],
    epics: [epic({ title: 'Running thing' }), epic({ issue: 29, status: 'needs_human', needsHumanReason: 'why', title: 'Stuck thing' }), epic({ issue: 33, title: null })],
    done: [{ repo: 'AshuLab/carrier', issue: 28, title: 'Done thing', labels: [], prNumber: 44, finishedAt: now - 7_200_000, executionId: null }],
  });
  const out = plain(titled);
  expect(out).toContain('┃ AshuLab/carrier #31  Running thing\n');
  expect(out).toContain('   AshuLab/web #30  Queued thing\n');
  expect(out).toContain('   AshuLab/carrier #29  Stuck thing\n   why');
  expect(out).toContain('#28 · PR #44 · 2h 00m ago  Done thing');
  expect(out).toContain('   AshuLab/web #31\n   AshuLab/web #32\n'); // no title: no trailing gap
  expect(out).toContain('┃ AshuLab/carrier #33\n');
  expect(renderDashboard(titled, { color: false, ui: { ...keysUi, selected: 'AshuLab/carrier#31' } }).join('\n')).toContain(' › AshuLab/carrier #31   Running thing');
});

test('a title never carries a control sequence to the terminal, nor makes a line wider than it', () => {
  const hostile = snap({
    queue: [{ repo: 'AshuLab/web', issue: 30, title: 'q\x1b[2Jq' }],
    epics: [epic({ title: 'a\x1b]0;pwned\x07b' }), epic({ issue: 29, status: 'needs_human', title: 't'.repeat(300) })],
    done: [{ repo: 'AshuLab/carrier', issue: 28, title: 'd\r\x1b[31md'.repeat(40), labels: [], prNumber: 44, finishedAt: now, executionId: null }],
  });
  expect(plain(hostile)).not.toMatch(/[\x07\x1b\r]/);
  expect(plain(hostile)).toContain('q [2Jq');
  for (const columns of [50, 60, 120]) for (const line of renderDashboard(hostile, { columns })) expect(visibleLength(line)).toBeLessThanOrEqual(Math.min(columns, 80));
});

test('a stopped epic shows why it needs a person, and just the row when it has no reason', () => {
  const out = plain(snap({ epics: [epic({ issue: 29, status: 'needs_human', needsHumanReason: 'review limit: round 5 of 5 still has requested changes' }), epic({ issue: 30, status: 'needs_human' })] }));
  expect(out).toContain('   AshuLab/carrier #29\n   review limit: round 5 of 5 still has requested changes\n   https://');
  expect(out).toContain('   AshuLab/carrier #30\n   https://');
  expect(out).not.toContain('needs_human');
});

test('a review or fix card lists up to three blocker titles and counts the rest; with none it adds nothing', () => {
  const titles = ['one', 'two', 'three', 'four', 'five'];
  const card = (stage: PanelEpic['stage'], n: number) => plain(snap({ epics: [epic({ stage, blockers: n, blockerTitles: titles.slice(0, n) })] }));
  expect(card('review', 0)).not.toContain('· one');
  expect(card('review', 0)).not.toContain('more');
  expect(card('review', 2)).toContain(' ┃   · one\n ┃   · two\n');
  expect(card('review', 2)).not.toContain('more');
  expect(card('fix', 3)).toContain('· three');
  expect(card('fix', 3)).not.toContain('more');
  const five = card('review', 5);
  expect(five).toContain(' ┃   · three\n ┃   … and 2 more');
  expect(five).not.toContain('· four');
  expect(card('ship', 2)).not.toContain('· one'); // only a review or fix has blockers to list
});

test('a blocker title or a reason never carries a control sequence, nor makes a line wider than the terminal', () => {
  const hostile = snap({
    epics: [epic({ stage: 'fix', blockers: 1, blockerTitles: ['b\x1b[2Jb\r\x07'.repeat(60)] }), epic({ issue: 29, status: 'needs_human', needsHumanReason: 'r\x1b]0;x\x07r'.repeat(60) })],
  });
  expect(plain(hostile)).not.toMatch(/[\x07\x1b\r]/);
  for (const columns of [50, 60, 120]) for (const line of renderDashboard(hostile, { columns })) expect(visibleLength(line)).toBeLessThanOrEqual(Math.min(columns, 80));
});

test('color is only styling: the same words, and none at all with color off', () => {
  const colored = renderDashboard(snap({ epics: [epic()] }), { color: true }).join('\n');
  expect(colored).toContain('\x1b[');
  expect(colored.replace(/\x1b\[[0-9;]*m/g, '')).toBe(plain(snap({ epics: [epic()] })));
  expect(plain(snap({ epics: [epic()] }))).not.toContain('\x1b');
});

test('no line is wider than the terminal, with styling in it, so the redraw can count on the line count', () => {
  const wide = snap({ epics: [epic({ prUrl: `https://github.com/AshuLab/carrier/pull/${'9'.repeat(80)}`, lastError: 'e'.repeat(200) })] });
  for (const columns of [50, 60, 120]) for (const line of renderDashboard(wide, { columns })) expect(visibleLength(line)).toBeLessThanOrEqual(Math.min(columns, 80));
  expect(fit('\x1b[31mabcdef\x1b[0m', 3)).toBe('\x1b[31mabc\x1b[0m'); // cut by visible characters, style kept and closed
  expect(fit('abc', 10)).toBe('abc');
});

const keysUi = { selected: null, mode: 'dashboard' as const, toast: null };

test('with keys: the hints replace "Ctrl+C stops it", and the selected row carries the pointer on its first line', () => {
  const s = snap({ slots: { busy: 1, total: 3 }, epics: [epic()], queue: [{ repo: 'AshuLab/web', issue: 30 }] });
  const out = plain({ ...s }).split('\n');
  expect(out.at(-1)).toBe('   Ctrl+C stops it'); // read-only: no hints
  const withKeys = renderDashboard(s, { color: false, ui: { ...keysUi, selected: 'AshuLab/carrier#31' } }).join('\n');
  expect(withKeys).toContain(' › AshuLab/carrier #31 \n ▌ [ship]'); // the pointer and a heavier bar on the selected card
  expect(withKeys).toContain('↑↓ select · enter open · r check now · p pause · ? help · q quit'); // no `l`: that epic has no agent output
  expect(withKeys).not.toContain('Ctrl+C stops it');
  const queued = renderDashboard(s, { color: false, ui: { ...keysUi, selected: 'AshuLab/web#30' } }).join('\n');
  expect(queued).toContain(' › AshuLab/web #30');
  expect(queued).toContain(' ┃ AshuLab/carrier #31'); // the others keep the light bar
});

test('a toast shows above the hints, and paused is a banner in the header', () => {
  const out = renderDashboard(snap({ paused: true }), { color: false, ui: { ...keysUi, toast: { text: 'Paused: no new epics will start', until: now + 1 } } }).join('\n');
  expect(out).toContain('▲ PAUSED: new epics wait in the queue (p resumes)');
  expect(out).toMatch(/› Paused: no new epics will start\n\n {3}r check now · p resume/);
});

test('the help screen lists the keys, and the logs screen shows the agent output of the selected epic', () => {
  const help = renderDashboard(snap(), { color: false, ui: { ...keysUi, mode: 'help' } }).join('\n');
  expect(help).toContain('KEYS');
  expect(help).toContain('enter     open its PR (or issue) in the browser');
  expect(help).toContain('esc back · q quit');
  expect(help).not.toContain('Idle.'); // the help replaces the body

  const s = snap({ slots: { busy: 1, total: 3 }, epics: [epic({ executionId: 'abcdef1234567' })] });
  const logs = renderDashboard(s, { color: false, ui: { ...keysUi, mode: 'logs', selected: 'AshuLab/carrier#31' }, logLines: ['▸ Bash git status', 'Reading the spec'] }).join('\n');
  expect(logs).toContain('AGENT OUTPUT · AshuLab/carrier#31 · abcdef12');
  expect(logs).toContain('   ▸ Bash git status\n   Reading the spec');
  const empty = renderDashboard(s, { color: false, ui: { ...keysUi, mode: 'logs', selected: 'AshuLab/carrier#31' } }).join('\n');
  expect(empty).toContain('(nothing written yet)');
});

test('a running card says what its agent is doing: three lines when selected, one when not; ↑↓ is not offered with a single row', () => {
  const s = snap({ slots: { busy: 2, total: 3 }, epics: [epic({ executionId: 'e1' }), epic({ issue: 32, executionId: 'e2' })] });
  const activity = (id: string, count: number) => ['one', 'two', 'three'].map((l) => `${id} ${l}`).slice(-count);
  const out = renderDashboard(s, { color: false, ui: { ...keysUi, selected: 'AshuLab/carrier#31' }, activity }).join('\n');
  expect(out).toContain('now  e1 one\n ▌      e1 two\n ▌      e1 three');
  expect(out).toContain('now  e2 three'); // the other card: the last line only
  expect(out).not.toContain('e2 two');
  expect(out).toContain('l logs');

  const alone = renderDashboard(snap({ epics: [epic({ executionId: 'e1' })] }), { color: false, ui: { ...keysUi, selected: 'AshuLab/carrier#31' } }).join('\n');
  expect(alone).not.toContain('↑↓');
});
