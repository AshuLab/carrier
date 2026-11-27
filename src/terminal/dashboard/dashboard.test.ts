import { expect, test } from 'vitest';
import { colorWanted, fit, quietAfterMs, renderDashboard, stuckAfterMs, unansweredLine, visibleLength, type DashboardOptions } from './dashboard.ts';
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

test('with no repos, idle says so instead of asking for a label in a repo that is not there', () => {
  const out = plain(snap({ repos: 0 }));
  expect(out).toContain('watching 0 repos ·');
  expect(out).toContain('No repos are watched yet');
  expect(out).not.toContain('Mark an epic');
});

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
  expect(out).toContain('┃ ship ▸ [review] ▸ fix · round ● ● ○ ○ ○');
  expect(out).toContain('3m 02s in stage · active 21s ago · blockers 1');
  expect(out).toContain('┃ https://github.com/AshuLab/api/pull/9'); // the PR once there is one
});

test('an epic in the stage lead (reported as review with lead set) shows the lead as the active stage, and an epic in review does not show it', () => {
  const lead = plain(snap({ epics: [epic({ stage: 'review', lead: true, round: 2 })] }));
  expect(lead).toContain('┃ ship ▸ review ▸ fix ▸ [lead] · round ● ● ○ ○ ○');
  expect(lead).not.toContain('[review]');
  expect(plain(snap({ epics: [epic({ stage: 'review', round: 2 })] }))).not.toContain('lead');
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

test('a ready-for-test epic with observations nobody answered says how many and why', () => {
  const done = { repo: 'AshuLab/carrier', issue: 28, title: 'Menu bar', labels: [], prNumber: 44, finishedAt: now - 7_200_000, executionId: null };
  expect(plain(snap({ done: [{ ...done, unansweredObservations: { count: 2, reason: 'already_taken' } }] }))).toContain('Menu bar\n   2 unanswered observations: pass already taken');
  expect(plain(snap({ done: [{ ...done, unansweredObservations: { count: 1, reason: 'last_round' } }] }))).toContain('1 unanswered observation: last round');
  // the reason is never cut, down to the 50-column floor
  for (const reason of ['already_taken', 'last_round'] as const) expect(plain(snap({ done: [{ ...done, unansweredObservations: { count: 12, reason } }] }), 50)).toContain(unansweredLine({ count: 12, reason }));
  expect(plain(snap({ done: [done] }))).not.toContain('unanswered');
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

test('a stopped epic that resumes by itself says in how long, and at the next check once the time has passed', () => {
  const out = (resumeAt?: number) => plain(snap({ epics: [epic({ issue: 29, status: 'needs_human', needsHumanReason: 'ran out of usage', ...(resumeAt !== undefined && { resumeAt }) })] }));
  expect(out(now + 5 * 3_600_000 + 12 * 60_000)).toContain('   ran out of usage\n   resumes by itself in 5h 12m\n   https://');
  expect(out(now - 1)).toContain('   resumes by itself at the next check');
  expect(out()).not.toContain('resumes');
});

test('a running card waiting to retry says in how long, and at the next check once the time has passed', () => {
  const out = (retryAt?: number) => plain(snap({ epics: [epic({ issue: 29, ...(retryAt !== undefined && { retryAt }) })] }));
  expect(out(now + 600_000)).toContain('retrying in 10m');
  expect(out(now - 1)).toContain('retrying at the next check');
  expect(out()).not.toContain('retrying');
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

const keysUi = { selected: null, mode: 'dashboard' as const, toast: null, closedOpen: false };

test('with keys: the hints replace "Ctrl+C stops it", and the selected row carries the pointer on its first line', () => {
  const s = snap({ slots: { busy: 1, total: 3 }, epics: [epic()], queue: [{ repo: 'AshuLab/web', issue: 30 }] });
  const out = plain({ ...s }).split('\n');
  expect(out.at(-1)).toBe('   Ctrl+C stops it'); // read-only: no hints
  const withKeys = renderDashboard(s, { color: false, ui: { ...keysUi, selected: 'AshuLab/carrier#31' } }).join('\n');
  expect(withKeys).toContain(' › AshuLab/carrier #31 \n ▌ [ship]'); // the pointer and a heavier bar on the selected card
  expect(withKeys).toContain('↑↓ select · enter open · c check now · p pause · ? help · q quit'); // no `l`: that epic has no agent output
  expect(withKeys).not.toContain('Ctrl+C stops it');
  const queued = renderDashboard(s, { color: false, ui: { ...keysUi, selected: 'AshuLab/web#30' } }).join('\n');
  expect(queued).toContain(' › AshuLab/web #30');
  expect(queued).toContain(' ┃ AshuLab/carrier #31'); // the others keep the light bar
});

test('a toast shows in a status bar under a rule, above the hints, with no pointer that could pass for a selected row; paused is a banner in the header', () => {
  const out = renderDashboard(snap({ paused: true }), { color: false, ui: { ...keysUi, toast: { text: 'Paused: no new epics will start', until: now + 1 } } }).join('\n');
  expect(out).toContain('▲ PAUSED: new epics wait in the queue (p to unpause)');
  expect(out).toMatch(/\n ─{20,}\n {3}Paused: no new epics will start\n {3}c check now · p unpause/);
  expect(out).not.toContain('› Paused');
  // without a toast the rule still closes the list; read-only has no status bar
  expect(renderDashboard(snap(), { color: false, ui: keysUi }).join('\n')).toMatch(/\n ─{20,}\n {3}c check now/);
  expect(renderDashboard(snap(), { color: false }).join('\n')).not.toContain('───\n');
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

test('a running card says what its agent is doing, three lines when selected, and with keys the other cards do not; ↑↓ is not offered with a single row', () => {
  const s = snap({ slots: { busy: 2, total: 3 }, epics: [epic({ executionId: 'e1' }), epic({ issue: 32, executionId: 'e2' })] });
  const activity = (id: string, count: number) => ['one', 'two', 'three'].map((l) => `${id} ${l}`).slice(-count);
  const out = renderDashboard(s, { color: false, ui: { ...keysUi, selected: 'AshuLab/carrier#31' }, activity }).join('\n');
  expect(out).toContain('now  e1 one\n ▌      e1 two\n ▌      e1 three');
  expect(out).not.toContain('e2'); // the other card is two lines: no agent output
  expect(out).toContain('l logs');
  // read-only (no selection to expand): every card is whole, with the last line of its agent
  expect(renderDashboard(s, { color: false, activity }).join('\n')).toContain('now  e2 three');

  const alone = renderDashboard(snap({ epics: [epic({ executionId: 'e1' })] }), { color: false, ui: { ...keysUi, selected: 'AshuLab/carrier#31' } }).join('\n');
  expect(alone).not.toContain('↑↓');
});

// A running epic's stages as the engine answers them: newest first.
const session = (stage: 'ship' | 'review' | 'fix', minutesAgo: number, tookMin: number | null, outcome: 'completed' | 'changes_requested' | 'needs_human' | null, over: object = {}) => ({
  executionId: `${stage}-${minutesAgo}`,
  stage,
  role: stage === 'review' ? ('reviewer' as const) : ('author' as const),
  round: null,
  agent: { harness: 'claude' as const, model: 'm', provider: null },
  profile: null,
  status: tookMin === null ? ('running' as const) : ('finished' as const),
  startedAt: now - minutesAgo * 60_000,
  finishedAt: tookMin === null ? null : now - (minutesAgo - tookMin) * 60_000,
  resume: null,
  result: outcome === null ? null : { outcome, summary: 's', verification: null, reason: null },
  failure: null,
  ...over,
});
const history = [session('fix', 2, null, null, { round: 1 }), session('review', 18, 4, 'changes_requested', { round: 1 }), session('ship', 32, 14, 'completed')];

test('with a detail provider a running card lists its stages with how each went, the running one in brackets', () => {
  const out = plain(snap({ epics: [epic({ stage: 'fix', round: 1 })] }), 80);
  expect(out).not.toContain('changes'); // without a provider the card is as before
  const withDetail = renderDashboard(snap({ epics: [epic({ stage: 'fix', round: 1 })] }), { columns: 80, color: false, detail: () => history }).join('\n');
  expect(withDetail).toContain('┃ ship ✓ 14m 00s · review ↻ changes round 1 4m 00s · [fix] round 1 2m 00s\n');
  expect(renderDashboard(snap({ epics: [epic()] }), { color: false, detail: () => null }).join('\n')).toBe(plain(snap({ epics: [epic()] }))); // nothing known: as before
  expect(renderDashboard(snap({ epics: [epic()] }), { color: false, detail: () => [] }).join('\n')).toBe(plain(snap({ epics: [epic()] })));
});

test('a stage with no result shows no outcome, and a needs_human one says so', () => {
  const failed = [session('ship', 10, null, null), session('ship', 20, 5, null, { status: 'failed' }), session('ship', 30, 5, 'needs_human')];
  const out = renderDashboard(snap({ epics: [epic()] }), { color: false, detail: () => failed }).join('\n');
  expect(out).toContain('┃ ship ▲ needs you 5m 00s · ship 5m 00s · [ship] 10m 00s\n');
});

test('a failed stage shows its kind where a completed one shows its outcome, and one with no kind is drawn as before', () => {
  const failure = { kind: 'killed' as const, detail: 'SIGKILL', exitCode: null, signal: 'SIGKILL', hostFreeMemMb: null, hostLoad: null };
  const failed = [session('ship', 10, null, null), session('ship', 20, 5, null, { status: 'failed' }), session('ship', 30, 4, null, { status: 'failed', failure })];
  const out = renderDashboard(snap({ epics: [epic()] }), { color: false, detail: () => failed }).join('\n');
  expect(out).toContain('┃ ship ✗ killed 4m 00s · ship 5m 00s · [ship] 10m 00s\n');
});

test('the provider is asked once per epic while its snapshot is unchanged, and again only for the epic that changed', () => {
  const calls: string[] = [];
  const detail = (repo: string, issue: number) => (calls.push(`${repo}#${issue}`), history);
  const a = epic({ issue: 1, executionId: 'e1' });
  const b = epic({ issue: 2, executionId: 'e2' });
  const draw = (...epics: PanelEpic[]) => renderDashboard(snap({ epics }), { color: false, detail });
  draw(a, b);
  draw(a, b);
  draw(a, b);
  expect(calls).toEqual(['AshuLab/carrier#1', 'AshuLab/carrier#2']);
  for (const change of [{ stage: 'review' as const }, { round: 2 }, { blockers: 3 }, { executionId: 'e9' }]) {
    calls.length = 0;
    const changed = { ...a, ...change };
    draw(changed, b);
    draw(changed, b);
    expect(calls).toEqual(['AshuLab/carrier#1']);
    draw(a, b); // back to a state that was cached under another signature: asked once more
    calls.length = 0;
  }
});

test('the stages line is only styling, never wider than the terminal, and drops the oldest stages first', () => {
  const many = Array.from({ length: 12 }, (_, i) => session(i % 2 ? 'fix' : 'review', 12 * 20 - i * 20, 3, 'changes_requested', { round: 12 - i, executionId: `x${i}` })).reverse();
  many.unshift(session('fix', 1, null, null, { round: 13 }));
  const s = snap({ epics: [epic({ stage: 'fix', round: 5 })] });
  for (const columns of [50, 60, 120]) {
    const lines = renderDashboard(s, { columns, detail: () => many });
    for (const line of lines) expect(visibleLength(line)).toBeLessThanOrEqual(Math.min(columns, 80));
    expect(lines.join('\n').replace(/\x1b\[[0-9;]*m/g, '')).toContain('[fix] round 13'); // the stage that is running is never the one cut
  }
  const colored = renderDashboard(s, { color: true, detail: () => history }).join('\n');
  expect(colored.replace(/\x1b\[[0-9;]*m/g, '')).toBe(renderDashboard(s, { color: false, detail: () => history }).join('\n'));
  expect(renderDashboard(s, { color: false, detail: () => many }).join('\n')).toContain('… ');
});

test('a repo GitHub refused is listed with its error; healthy repos or no watched list add nothing', () => {
  const ok = { repo: 'AshuLab/carrier', ok: true, error: null };
  const bad = (repo: string, error: string | null) => ({ repo, ok: false, error });
  const none = plain(snap());
  expect(plain(snap({ watched: [ok] }))).toBe(none);
  expect(plain(snap({ watched: [] }))).toBe(none);
  const one = plain(snap({ watched: [ok, bad('AshuLab/api', 'HTTP 404: Not Found')] }));
  expect(one).toContain('REPOS GITHUB REFUSED ▲\n   AshuLab/api  HTTP 404: Not Found');
  expect(one).not.toContain('AshuLab/carrier  ');
  const two = plain(snap({ watched: [bad('AshuLab/api', 'HTTP 404'), bad('AshuLab/web', 'bad credentials')] }));
  expect(two).toContain('AshuLab/api  HTTP 404\n   AshuLab/web  bad credentials');
});

test('a refused repo error loses its control sequences and never makes a line wider than the terminal', () => {
  const s = snap({ watched: [{ repo: 'AshuLab/api', ok: false, error: `\x1b[2Jwipe${'x'.repeat(200)}` }] });
  const out = renderDashboard(s, { columns: 60, color: false });
  expect(out.join('\n')).not.toContain('\x1b');
  expect(out.join('\n')).toContain('AshuLab/api   [2Jwipe');
  for (const line of renderDashboard(s, { columns: 60 })) expect(visibleLength(line)).toBeLessThanOrEqual(60);
});

test('q stops Carrier in the foreground and leaves it running in watch: hints, help and the read-only footer say which', () => {
  const view = (quit?: 'stop' | 'leave', ui: DashboardOptions['ui'] = keysUi) => renderDashboard(snap(), { color: false, ui, quit }).join('\n');
  expect(view()).toContain('p pause · ? help · q quit');
  expect(view(undefined, { ...keysUi, mode: 'help' })).toContain('q         stop Carrier (same as Ctrl+C)');
  expect(view('leave')).toContain('p pause · ? help · q leave');
  expect(view('leave', { ...keysUi, mode: 'help' })).toContain('q         leave (Carrier keeps running)');
  expect(view('leave', { ...keysUi, mode: 'help' })).not.toContain('stop Carrier');
  expect(view('leave', { ...keysUi, mode: 'help' })).toContain('esc back · q leave');
  expect(renderDashboard(snap(), { color: false, quit: 'leave' }).at(-1)).toBe('   Ctrl+C leaves it running');
});

test('a needs-you row and a ready-for-test row show their stages too, asked once per epic', () => {
  const calls: string[] = [];
  const detail = (repo: string, issue: number) => (calls.push(`${repo}#${issue}`), history);
  const s = snap({
    epics: [epic({ issue: 29, status: 'needs_human', stage: 'review', needsHumanReason: 'inconclusive review' })],
    done: [{ repo: 'AshuLab/carrier', issue: 28, title: 'Menu bar', labels: [], prNumber: 44, finishedAt: now - 7_200_000, executionId: 'x1' }],
  });
  const draw = () => renderDashboard(s, { columns: 80, color: false, detail }).join('\n');
  const out = draw();
  draw();
  expect(out).toContain('inconclusive review\n   ship ✓ 14m 00s · review ↻ changes round 1 4m 00s · [fix] round 1 2m 00s\n');
  expect(out).toContain('Menu bar\n   ship ✓ 14m 00s ·');
  expect(calls).toEqual(['AshuLab/carrier#29', 'AshuLab/carrier#28']);
  expect(renderDashboard(s, { color: false }).join('\n')).not.toContain('ship ✓');
  for (const line of renderDashboard(s, { columns: 50, detail })) expect(visibleLength(line)).toBeLessThanOrEqual(50);
});

const fin = (issue: number, over: Partial<NonNullable<PanelSnapshot['finished']>[number]> = {}): NonNullable<PanelSnapshot['finished']>[number] => ({
  repo: 'AshuLab/carrier', issue, title: `Epic ${issue}`, labels: [], prNumber: 100 + issue, finishedAt: now - 3_600_000 * issue, status: 'merged', cancelReason: null, executionId: `exec-${issue}`, ...over,
});

test('merged and cancelled epics get a DONE and a CANCELLED section after READY FOR TEST; the cancelled row shows its reason', () => {
  const out = plain(snap({
    done: [{ repo: 'AshuLab/carrier', issue: 28, title: 'Menu bar', labels: [], prNumber: 44, finishedAt: now - 7_200_000, executionId: null }],
    finished: [fin(1), fin(2, { status: 'cancelled', prNumber: null, cancelReason: 'final PR closed' })],
  }));
  expect(out).toContain('\n DONE\n   AshuLab/carrier #1 · PR #101 · 1h 00m ago  Epic 1\n');
  expect(out).toContain('\n CANCELLED\n   AshuLab/carrier #2 · 2h 00m ago  Epic 2\n   final PR closed\n');
  expect(out.indexOf('READY FOR TEST')).toBeLessThan(out.indexOf('DONE'));
  expect(out.indexOf('DONE')).toBeLessThan(out.indexOf('CANCELLED'));
});

test('a section lists the ten most recent and counts the rest; with ten or fewer there is no such line, and an empty section is not drawn', () => {
  const eleven = plain(snap({ finished: Array.from({ length: 11 }, (_, i) => fin(i + 1)) }));
  expect(eleven).toContain('#10 ');
  expect(eleven).not.toContain('#11 ');
  expect(eleven).toContain('   +1 more\n');
  const ten = plain(snap({ finished: Array.from({ length: 10 }, (_, i) => fin(i + 1)) }));
  expect(ten).toContain('#10 ');
  expect(ten).not.toContain('more');
  expect(ten).not.toContain('CANCELLED');
  const none = plain(snap({ finished: [] }));
  expect(none).not.toContain('DONE');
  expect(none).not.toContain('CANCELLED');
  expect(plain(snap())).not.toContain('DONE'); // an engine that sends no `finished`
});

test('finished epics do not suppress the Idle message, and their sections show below it', () => {
  const out = plain(snap({ finished: [fin(1)] }));
  expect(out).toContain('Idle.');
  expect(out.indexOf('Idle.')).toBeLessThan(out.indexOf('DONE'));
});

test('a finished title or reason never carries a control sequence', () => {
  const out = plain(snap({ finished: [fin(1, { status: 'cancelled', title: 'a\x1b[2Jb', cancelReason: 'c\x07d' })] }));
  expect(out).not.toMatch(/[\x07\x1b\r]/);
  expect(out).toContain('a [2Jb');
});

test('the logs screen names the execution of a finished row', () => {
  const out = renderDashboard(snap({ finished: [fin(1)] }), { color: false, ui: { ...keysUi, mode: 'logs', selected: 'AshuLab/carrier#1' }, logLines: ['hi'] }).join('\n');
  expect(out).toContain('AGENT OUTPUT · AshuLab/carrier#1 · exec-1');
});

test('an epic with no stage yet says it is starting, and a read-only dashboard offers no keys', () => {
  const s = snap({ epics: [epic({ stage: null, options: { names: ['claude', 'codex'], author: 'claude', reviewer: 'codex' } })] });
  const out = renderDashboard(s, { color: false }).join('\n');
  expect(out).toContain('starting');
  expect(out).not.toContain('choice');
  expect(out).toContain('Ctrl+C stops it');
});

// --- a round of several reviewers: how many gave a verdict, and why each other gave none ---

const severalReviewers = { given: 1, of: 3, none: [{ slot: 'seguridad-api' as const, why: 'cannot verify\x1b[2J the migration' }, { slot: 'usabilidad' as const, why: 'ran out of usage' }] };

test('a running card with several reviewers shows the count and the reason of each reviewer without a verdict, after the stage line', () => {
  const out = plain(snap({ epics: [epic({ stage: 'fix', round: 1, reviewers: severalReviewers })] }));
  expect(out).toContain('┃ 12m 40s in stage · active 8s ago\n ┃ reviewers 1 of 3 gave a verdict\n ┃   · seguridad-api: cannot verify [2J the migration\n ┃   · usabilidad: ran out of usage');
  expect(out).not.toMatch(/\x1b\[2J/);
});

test('a card with every verdict shows only the count, and an epic with one reviewer shows nothing new', () => {
  expect(plain(snap({ epics: [epic({ stage: 'fix', round: 1, reviewers: { given: 2, of: 2, none: [] } })] }))).toMatch(/┃ reviewers 2 of 2 gave a verdict\n(?! ┃   ·)/);
  expect(plain(snap({ epics: [epic({ stage: 'fix', round: 1 })] }))).not.toContain('reviewers');
});

test('an epic that needs you, and one ready for test, show the count and the reasons under their rows', () => {
  const done = { repo: 'AshuLab/carrier', issue: 28, title: 'Menu bar', labels: [], prNumber: 44, finishedAt: now - 7_200_000, executionId: null, reviewers: { given: 1, of: 2, none: [{ slot: 'seguridad-api' as const, why: 'ran out of usage' }] } };
  const out = plain(snap({ epics: [epic({ issue: 29, status: 'needs_human', needsHumanReason: 'no reviewer gave a verdict in round 1', reviewers: { given: 0, of: 2, none: [{ slot: 'reviewer' as const, why: 'cannot verify' }, { slot: 'seguridad-api' as const, why: 'ran out of usage' }] } })], done: [done] }));
  expect(out).toContain('NEEDS YOU ▲\n   AshuLab/carrier #29\n   no reviewer gave a verdict in round 1\n   reviewers 0 of 2 gave a verdict\n     · reviewer: cannot verify\n     · seguridad-api: ran out of usage');
  expect(out).toContain('READY FOR TEST ✔\n   AshuLab/carrier #28 · PR #44 · 2h 00m ago  Menu bar\n   reviewers 1 of 2 gave a verdict\n     · seguridad-api: ran out of usage');
});

test('the lines of the reviewers are never cut away by the 50-column floor of the count', () => {
  const out = plain(snap({ epics: [epic({ stage: 'fix', round: 1, reviewers: { given: 1, of: 4, none: [] } })] }), 50);
  expect(out).toContain('reviewers 1 of 4 gave a verdict');
});

// --- with keys: the summary, the compact cards, the CLOSED section and the window of a terminal that is too short ---

const strip = (lines: string[]) => lines.map((l) => l.replace(/\x1b\[[0-9;]*m/g, ''));
const withKeys = (s: PanelSnapshot, over: Omit<DashboardOptions, 'ui'> & { ui?: Partial<NonNullable<DashboardOptions['ui']>> } = {}) =>
  strip(renderDashboard(s, { color: false, ...over, ui: { ...keysUi, ...over.ui } }));

test('the header sums up what there is, leaves out what is zero, and says nothing when there is nothing', () => {
  const s = snap({
    epics: [epic(), epic({ issue: 32 }), epic({ issue: 33, status: 'needs_human' })],
    queue: [{ repo: 'AshuLab/web', issue: 1 }, { repo: 'AshuLab/web', issue: 2 }],
    done: [{ repo: 'AshuLab/carrier', issue: 28, title: null, labels: [], prNumber: 44, finishedAt: now, executionId: null }],
  });
  expect(plain(s)).toContain('watching 2 repos · next check in 3m 12s\n   2 running · 2 queued · ▲ 1 needs you · ✔ 1 ready\n');
  expect(plain(snap({ queue: [{ repo: 'AshuLab/web', issue: 1 }] }))).toContain('\n   1 queued\n');
  expect(plain(snap())).not.toMatch(/running|queued|needs you|ready\n/); // idle: no line
});

test('with keys an unselected running card is two lines and the selected one has everything; read-only keeps every card whole', () => {
  const s = snap({
    slots: { busy: 2, total: 3 },
    epics: [
      epic({ title: 'First', stage: 'review', round: 2, blockers: 2, blockerTitles: ['a', 'b'], slices: { done: 1, total: 3 }, prUrl: 'https://github.com/AshuLab/carrier/pull/9', reviewers: { given: 1, of: 2, none: [{ slot: 'reviewer', why: 'ran out of usage' }] }, executionId: 'e1' }),
      epic({ issue: 32, title: 'Second', stage: 'fix', round: 1, prUrl: 'https://github.com/AshuLab/carrier/pull/10', executionId: 'e2' }),
    ],
  });
  const activity = (id: string) => [`${id} working`];
  const out = withKeys(s, { activity, ui: { selected: 'AshuLab/carrier#32' } }).join('\n');
  // the first card: a title and one line, with no URL, no agent output, no reviewers and no blocker titles
  expect(out).toContain(' ┃ AshuLab/carrier #31  First\n ┃ [review] · round ●●○○○ · blockers 2 · slices 1/3 · 12m 40s · active 8s ago\n\n');
  expect(out).not.toContain('pull/9');
  expect(out).not.toContain('e1 working');
  expect(out).not.toContain('reviewers 1 of 2');
  expect(out).not.toContain('  · a\n');
  // the selected one is the whole card
  expect(out).toContain(' › AshuLab/carrier #32   Second\n');
  expect(out).toContain(' ▌ ship ▸ review ▸ [fix] · round ● ○ ○ ○ ○\n ▌ 12m 40s in stage · active 8s ago\n ▌ https://github.com/AshuLab/carrier/pull/10\n ▌ now  e2 working');
  // selecting the first expands it, and its reviewers show again
  const first = withKeys(s, { activity, ui: { selected: 'AshuLab/carrier#31' } }).join('\n');
  expect(first).toContain('reviewers 1 of 2 gave a verdict\n ▌   · reviewer: ran out of usage');
  expect(first).toContain('  · a\n');
  // read-only: nothing is selected and nothing is folded
  const readOnly = plain(s);
  expect(readOnly).toContain('┃ https://github.com/AshuLab/carrier/pull/9');
  expect(readOnly).toContain('┃ reviewers 1 of 2 gave a verdict');
});

test('a compact card spaces the round dots when the line has room, and closes them up only when the spaces would cut the times', () => {
  const roomy = withKeys(snap({ epics: [epic({ stage: 'review', round: 2, blockers: 2 }), epic({ issue: 32 })] }), { ui: { selected: 'AshuLab/carrier#32' } }).join('\n');
  expect(roomy).toContain(' ┃ [review] · round ● ● ○ ○ ○ · blockers 2 · 12m 40s · active 8s ago\n');
  const full = withKeys(snap({ epics: [epic({ stage: 'review', round: 2, blockers: 2, slices: { done: 1, total: 3 } }), epic({ issue: 32 })] }), { ui: { selected: 'AshuLab/carrier#32' } }).join('\n');
  expect(full).toContain('round ●●○○○ · blockers 2 · slices 1/3 · 12m 40s · active 8s ago'); // 81 columns spaced: it would lose the end
});

test('a compact card keeps what is wrong: the retry and the error', () => {
  const out = withKeys(snap({ epics: [epic({ retryAt: now + 120_000, lastError: 'api_error 529' }), epic({ issue: 32 })] }), { ui: { selected: 'AshuLab/carrier#32' } }).join('\n');
  expect(out).toContain(' ┃ [ship] · 12m 40s · active 8s ago\n ┃ retrying in 2m 00s\n ┃ error: api_error 529\n');
});

test('a compact card fits the narrowest panel with its blockers, slices and times, and a stage that is just starting', () => {
  const s = snap({ epics: [epic({ stage: 'review', round: 5, maxReviews: 5, blockers: 12, slices: { done: 10, total: 12 }, stageSince: now - 5 * 3_600_000 }), epic({ issue: 32, stage: null, lastActivityAt: null })] });
  const out = withKeys(s, { columns: 80, ui: { selected: 'AshuLab/carrier#32' } });
  expect(out.join('\n')).toContain(' ┃ [review] · round ●●●●● · blockers 12 · slices 10/12 · 5h 00m · active 8s ago\n');
  expect(out.join('\n')).toContain(' › AshuLab/carrier #32 \n ▌ starting\n');
  expect(out.join('\n')).toContain('no activity yet');
});

test('the CLOSED heading is a row: selected it carries the pointer and the hint says enter opens or folds it', () => {
  const s = snap({ finished: [fin(1), fin(2)] });
  const folded = withKeys(s, { ui: { selected: 'closed' } }).join('\n');
  expect(folded).toContain('› CLOSED 2 ▸ '); // pointer and a highlighted label, like a selected card
  expect(folded).toContain('enter open closed');
  expect(folded).not.toContain('f show closed'); // enter says it already
  const open = withKeys(s, { ui: { selected: 'closed', closedOpen: true } }).join('\n');
  expect(open).toContain('› CLOSED 2 ▾ ');
  expect(open).toContain('enter fold');
  expect(open).not.toContain('d dismiss'); // the heading is not an epic
  expect(withKeys(s, { ui: { selected: 'AshuLab/carrier#1', closedOpen: true } }).join('\n')).toContain('\n CLOSED 2 ▾\n'); // not selected: no pointer
});

const closed = (n: number) => Array.from({ length: n }, (_, i) => fin(i + 1));

test('with keys the closed epics are one section that starts folded: the count, and no rows', () => {
  const s = snap({ finished: [fin(1), fin(2), fin(3, { status: 'cancelled', prNumber: null, cancelReason: 'final PR closed' })] });
  const folded = withKeys(s).join('\n');
  expect(folded).toContain('\n CLOSED 3 ▸\n');
  expect(folded).not.toContain('Epic 1');
  expect(folded).not.toContain('DONE');
  expect(folded).toContain('f show closed');
  const open = withKeys(s, { ui: { closedOpen: true } }).join('\n');
  expect(open).toContain('\n CLOSED 3 ▾\n   DONE\n   AshuLab/carrier #1 · PR #101 · 1h 00m ago  Epic 1\n   AshuLab/carrier #2 · PR #102 · 2h 00m ago  Epic 2\n   CANCELLED\n   AshuLab/carrier #3 · 3h 00m ago  Epic 3\n   final PR closed\n');
  expect(open).toContain('f hide closed');
  expect(open.indexOf('READY')).toBe(-1); // not drawn: there are none
  expect(withKeys(snap(), { ui: { closedOpen: true } }).join('\n')).not.toContain('CLOSED'); // no closed epics, no section
  expect(withKeys(snap()).join('\n')).not.toContain('f show closed');
});

test('the count of the CLOSED section is every closed epic, the listing is ten of each kind, and ready for test stays above it', () => {
  const s = snap({ done: [{ repo: 'AshuLab/carrier', issue: 28, title: 'Menu bar', labels: [], prNumber: 44, finishedAt: now - 7_200_000, executionId: null }], finished: closed(12) });
  const open = withKeys(s, { ui: { closedOpen: true } }).join('\n');
  expect(open).toContain('CLOSED 12 ▾');
  expect(open).toContain('   +2 more');
  expect(open.indexOf('READY FOR TEST')).toBeLessThan(open.indexOf('CLOSED'));
  expect(withKeys(s).join('\n')).toContain('READY FOR TEST ✔'); // ready is never folded
});

test('d is offered for a closed row when the program can dismiss, and in the help only then', () => {
  const s = snap({ finished: [fin(1)] });
  const ui = { closedOpen: true, selected: 'AshuLab/carrier#1' };
  expect(withKeys(s, { ui, dismiss: true }).join('\n')).toContain('d dismiss');
  expect(withKeys(s, { ui }).join('\n')).not.toContain('d dismiss'); // no way to do it
  expect(withKeys(snap({ epics: [epic()], finished: [fin(1)] }), { ui: { closedOpen: true, selected: 'AshuLab/carrier#31' }, dismiss: true }).join('\n')).not.toContain('d dismiss'); // not a closed row
  expect(withKeys(s, { ui: { mode: 'help' }, dismiss: true }).join('\n')).toContain('d         dismiss the selected closed epic');
  expect(withKeys(s, { ui: { mode: 'help' } }).join('\n')).not.toContain('dismiss');
  expect(withKeys(s, { ui: { mode: 'help' } }).join('\n')).toContain('f         show or hide the closed epics');
});

// A busy panel: five cards, a queue, the ones that need a person, ready ones and closed ones.
const busy = (selected: string | null) =>
  snap({
    slots: { busy: 5, total: 5 },
    epics: [
      ...Array.from({ length: 5 }, (_, i) => epic({ issue: 10 + i, title: `Running ${i}`, stage: 'review', round: 1, blockers: 1, blockerTitles: ['x'], prUrl: `https://github.com/AshuLab/carrier/pull/${i}`, executionId: `e${i}` })),
      epic({ issue: 20, status: 'needs_human', needsHumanReason: 'stuck', executionId: null }),
    ],
    queue: Array.from({ length: 4 }, (_, i) => ({ repo: 'AshuLab/web', issue: 30 + i, title: `Queued ${i}` })),
    done: [{ repo: 'AshuLab/carrier', issue: 28, title: 'Menu bar', labels: [], prNumber: 44, finishedAt: now - 7_200_000, executionId: null }],
    finished: closed(6),
  });
const keysOf = (s: PanelSnapshot, closedOpen: boolean) => [...s.epics.filter((e) => e.status === 'running').map((e) => `${e.repo}#${e.issue}`), ...s.queue.map((q) => `${q.repo}#${q.issue}`), 'AshuLab/carrier#20', 'AshuLab/carrier#28', ...(closedOpen ? closed(6).map((f) => `${f.repo}#${f.issue}`) : [])];

test('given the rows of the terminal the dashboard never reaches them, whichever row is selected and wherever the window falls', () => {
  for (const rows of [12, 16, 24, 40]) {
    for (const closedOpen of [false, true]) {
      const s = busy(null);
      for (const selected of keysOf(s, closedOpen)) {
        const lines = withKeys(s, { rows, ui: { selected, closedOpen } });
        expect(lines.length, `${rows} rows, ${selected}`).toBeLessThanOrEqual(rows - 1);
        const text = lines.join('\n');
        const name = selected.replace('AshuLab/', '').replace('#', ' #');
        expect(text, `${rows} rows: ${selected} is in view`).toContain(name.replace('carrier ', 'carrier ').replace('web ', 'web '));
        expect(text).toContain('◆ CARRIER'); // the header and the footer stay
        expect(text).toContain('q quit');
        expect(text).toContain('Slots');
        expect(lines.some((l) => l.includes('›'))).toBe(true); // and the selection carries the pointer
      }
    }
  }
});

test('the window says how many lines hide above and below, and nothing when it all fits or when no rows are given', () => {
  const s = busy(null);
  const top = withKeys(s, { rows: 24, ui: { selected: 'AshuLab/carrier#10' } });
  expect(top.join('\n')).not.toMatch(/↑ \d+ more/);
  expect(top.join('\n')).toMatch(/↓ \d+ more lines\n ─+\n/);
  const middle = withKeys(s, { rows: 24, ui: { selected: 'AshuLab/web#31' } }).join('\n');
  expect(middle).toMatch(/Slots .*\n {3}↑ \d+ more lines\n/);
  expect(middle).toMatch(/ {3}↓ \d+ more lines\n/);
  const end = withKeys(s, { rows: 24, ui: { selected: 'AshuLab/carrier#28' } }).join('\n');
  expect(end).toMatch(/↑ \d+ more/);
  expect(end).not.toMatch(/↓ \d+ more/);
  const whole = withKeys(s, { ui: { selected: 'AshuLab/carrier#10' } });
  expect(whole.join('\n')).not.toMatch(/more lines/);
  expect(whole.length).toBeGreaterThan(24);
  expect(withKeys(s, { rows: 200, ui: { selected: 'AshuLab/carrier#10' } })).toEqual(whole); // tall enough: not a line changed
});

test('the window begins and ends between rows, and never leaves a heading alone at its foot', () => {
  const s = busy(null);
  for (const selected of keysOf(s, true)) {
    const lines = withKeys(s, { rows: 22, ui: { selected, closedOpen: true } });
    const at = lines.findIndex((l) => /↑ \d+ more/.test(l));
    if (at !== -1) expect(lines[at + 1]).not.toBe(''); // a row right under the "more"
    const below = lines.findIndex((l) => /↓ \d+ more/.test(l));
    if (below !== -1) expect(lines[below - 1]).not.toMatch(/^ [A-Z][A-Z ]+[▲✔▸▾]?$/); // not a heading
  }
});

test('a row taller than the window shows from its top, with the footer in place', () => {
  const s = snap({ epics: [epic({ stage: 'review', blockers: 5, blockerTitles: ['a', 'b', 'c', 'd', 'e'], executionId: 'e1' })] });
  const lines = withKeys(s, { rows: 12, activity: () => ['one', 'two', 'three'], ui: { selected: 'AshuLab/carrier#31' } });
  expect(lines.length).toBeLessThanOrEqual(11);
  expect(lines.join('\n')).toContain('› AshuLab/carrier #31');
  expect(lines.at(-1)).toContain('q quit');
});

test('the logs screen keeps its title and shows the end of the output when the terminal is short; so does the help', () => {
  const s = snap({ epics: [epic({ executionId: 'abcdef1234567' })] });
  const logLines = Array.from({ length: 18 }, (_, i) => `line ${i}`);
  const logs = withKeys(s, { rows: 12, logLines, ui: { mode: 'logs', selected: 'AshuLab/carrier#31' } });
  expect(logs.length).toBeLessThanOrEqual(11);
  expect(logs.join('\n')).toContain('AGENT OUTPUT · AshuLab/carrier#31 · abcdef12');
  expect(logs.join('\n')).toContain('line 17'); // the last line, the one read
  expect(logs.join('\n')).not.toContain('line 0\n');
  expect(logs.join('\n')).toMatch(/↑ \d+ more lines/);
  expect(logs.at(-1)).toContain('esc back');
  const help = withKeys(s, { rows: 9, ui: { mode: 'help' } });
  expect(help.length).toBeLessThanOrEqual(8);
  expect(help.join('\n')).toContain('KEYS');
  expect(help.at(-1)).toContain('esc back');
});

test('the window of a short terminal is only styling too: the same words with the color on', () => {
  const s = busy(null);
  const ui = { ...keysUi, selected: 'AshuLab/web#31' };
  const colored = renderDashboard(s, { rows: 24, ui, color: true });
  expect(colored.length).toBeLessThanOrEqual(23);
  expect(strip(colored)).toEqual(renderDashboard(s, { rows: 24, ui, color: false }));
  for (const line of colored) expect(visibleLength(line)).toBeLessThanOrEqual(80);
});

// --- resuming from the panel, an agent gone quiet, and when to paint ---

const stoppedEpic = (over: Partial<PanelEpic> = {}) => epic({ issue: 9, status: 'needs_human', needsHumanReason: 'the review limit', executionId: null, ...over });

test('r is listed for a stopped row only when the program can resume, and the help lists it', () => {
  const s = snap({ epics: [epic(), stoppedEpic()] });
  expect(withKeys(s, { resume: true, ui: { selected: 'AshuLab/carrier#9' } }).join('\n')).toContain('r resume');
  expect(withKeys(s, { ui: { selected: 'AshuLab/carrier#9' } }).join('\n')).not.toContain('r resume'); // the program cannot
  expect(withKeys(s, { resume: true, ui: { selected: 'AshuLab/carrier#31' } }).join('\n')).not.toContain('r resume'); // a running row
  expect(withKeys(s, { resume: true, ui: { mode: 'help' } }).join('\n')).toMatch(/r +resume the selected stopped epic/);
  expect(withKeys(s, { ui: { mode: 'help' } }).join('\n')).not.toContain('resume the selected');
});

test('a resume waiting for its second r says what it will do, in the status bar, until answered or withdrawn', () => {
  const s = snap({ epics: [stoppedEpic()] });
  const out = withKeys(s, { resume: true, ui: { selected: 'AshuLab/carrier#9', confirm: 'AshuLab/carrier#9' } }).join('\n');
  expect(out).toMatch(/─+\n {3}Resume AshuLab\/carrier#9\? It starts again from ship, on the same agents\.\n {3}r confirms · any other key cancels\n/);
  expect(out).toContain('r confirm ·'); // the key list says the same
  expect(out).not.toContain('quota');
  // one that stopped on its quota points at the way to pick another agent, and every line fits the narrowest panel
  const quota = snap({ epics: [stoppedEpic({ needsHumanCode: 'epic.stop.usageLimit' })] });
  const asking = { resume: true, ui: { selected: 'AshuLab/carrier#9', confirm: 'AshuLab/carrier#9' } };
  expect(withKeys(quota, asking).join('\n')).toContain('It ran out of usage: carrier restart lets you pick another agent.');
  for (const line of withKeys(quota, { ...asking, columns: 50 })) expect(line.length).toBeLessThanOrEqual(50);
  // a toast does not replace it, and without a confirmation the toast shows as before
  expect(withKeys(s, { resume: true, ui: { selected: 'AshuLab/carrier#9', confirm: 'AshuLab/carrier#9', toast: { text: 'Checking GitHub now…', until: now + 1 } } }).join('\n')).not.toContain('Checking GitHub');
  expect(withKeys(s, { resume: true, ui: { selected: 'AshuLab/carrier#9', toast: { text: 'Checking GitHub now…', until: now + 1 } } }).join('\n')).toContain('Checking GitHub now…');
});

test('a running agent that wrote nothing for a while is marked ▲, and painted yellow and then red', () => {
  const card = (silent: number, over: Partial<PanelEpic> = {}) => renderDashboard(snap({ epics: [epic({ lastActivityAt: now - silent, ...over })] }), { color: true }).join('\n');
  expect(card(quietAfterMs - 1000)).not.toContain('▲');
  expect(card(quietAfterMs)).toContain('\x1b[33mactive 5m 00s ago ▲\x1b[0m');
  expect(card(stuckAfterMs)).toContain('\x1b[31mactive 15m 00s ago ▲\x1b[0m');
  expect(card(stuckAfterMs).replace(/\x1b\[[0-9;]*m/g, '')).toContain('active 15m 00s ago ▲'); // visible with no color at all
  // no output at all counts from the stage's start, and an epic waiting out a retry is quiet on purpose
  expect(card(0, { lastActivityAt: null, stageSince: now - stuckAfterMs }).replace(/\x1b\[[0-9;]*m/g, '')).toContain('no activity yet ▲');
  expect(card(stuckAfterMs, { retryAt: now + 60_000 })).not.toContain('▲');
});

test('color is on unless NO_COLOR has any value or the terminal is dumb', () => {
  expect(colorWanted({})).toBe(true);
  expect(colorWanted({ NO_COLOR: '' })).toBe(true); // the convention: set and empty does not count
  expect(colorWanted({ NO_COLOR: '1' })).toBe(false);
  expect(colorWanted({ TERM: 'xterm-256color' })).toBe(true);
  expect(colorWanted({ TERM: 'dumb' })).toBe(false);
});
