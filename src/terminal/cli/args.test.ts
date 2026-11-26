import { expect, test } from 'vitest';
import { roleSlots, roleFlagSuffixes } from '../wizard/roles.ts';
import { parseCli, usage } from './args.ts';

test('a command and its flags become data', () => {
  const parsed = parseCli(['init', '--repo', 'A/a', '--repo', 'B/b', '--author', 'claude:sonnet', '--yes']);
  expect(parsed).toMatchObject({ ok: true, command: 'init', flags: { repo: ['A/a', 'B/b'], author: 'claude:sonnet', yes: true } });
});

test('no command means run, and --config and --help are flags of any command', () => {
  expect(parseCli(['--config', 'x.json'])).toMatchObject({ ok: true, command: undefined, flags: { config: 'x.json' } });
  expect(parseCli(['doctor', '--config', 'x.json'])).toMatchObject({ ok: true, command: 'doctor' });
  expect(parseCli(['-h'])).toMatchObject({ ok: true, flags: { help: true } });
  expect(parseCli([])).toMatchObject({ ok: true, command: undefined, flags: {} });
});

test('doctor takes --json as a flag', () => {
  expect(parseCli(['doctor', '--json'])).toMatchObject({ ok: true, command: 'doctor', flags: { json: true } });
});

test('an unknown command, a second word and an unknown flag are errors that say why, without exiting', () => {
  expect(parseCli(['frobnicate'])).toEqual({ ok: false, message: 'Unknown command: frobnicate' });
  expect(parseCli(['init', 'now'])).toEqual({ ok: false, message: 'Unknown command: init now' });
  const flag = parseCli(['--nope']);
  expect(flag).toMatchObject({ ok: false });
  expect(flag.ok === false && flag.message).toContain('--nope');
});

test('status is a command that takes no arguments', () => {
  expect(parseCli(['status', '--config', 'x.json'])).toMatchObject({ ok: true, command: 'status', flags: { config: 'x.json' } });
  expect(parseCli(['status', 'now'])).toEqual({ ok: false, message: 'Unknown command: status now' });
});

test('the usage names every command and every init flag', () => {
  for (const word of ['carrier init', 'carrier doctor', 'carrier schema', 'carrier start', 'carrier status', 'stop', 'pause', 'resume', 'check', 'carrier chat ', 'carrier chat-host', 'carrier config', '--repo', '--out', '--yes', '--config', '--json']) expect(usage()).toContain(word);
});

test('stop, pause, resume and check are commands that take no argument', () => {
  for (const command of ['stop', 'pause', 'resume', 'check']) {
    expect(parseCli([command, '--config', 'x.json'])).toMatchObject({ ok: true, command, flags: { config: 'x.json' } });
    expect(parseCli([command, 'now'])).toEqual({ ok: false, message: `Unknown command: ${command} now` });
  }
});

test('start takes the config flag and no other word', () => {
  expect(parseCli(['start', '--config', 'x.json'])).toMatchObject({ ok: true, command: 'start', flags: { config: 'x.json' } });
  expect(parseCli(['start', 'now'])).toEqual({ ok: false, message: 'Unknown command: start now' });
});

test('watch takes the config flag and no other word', () => {
  expect(parseCli(['watch', '--config', 'x.json'])).toMatchObject({ ok: true, command: 'watch', flags: { config: 'x.json' } });
  expect(parseCli(['watch', 'now'])).toEqual({ ok: false, message: 'Unknown command: watch now' });
  expect(usage()).toContain('carrier watch');
});

test('restart takes one owner/name#N and the option of each role', () => {
  expect(parseCli(['restart', 'AshuLab/carrier#12', '--author', 'codex', '--reviewer', 'claude', '--config', 'x.json'])).toMatchObject({
    ok: true, command: 'restart', target: { repo: 'AshuLab/carrier', issue: 12 }, flags: { author: 'codex', reviewer: 'claude', config: 'x.json' },
  });
  expect(parseCli(['restart', 'a.b/c_d-e#1'])).toMatchObject({ ok: true, target: { repo: 'a.b/c_d-e', issue: 1 } });
});

test.each(['', 'AshuLab/carrier', 'AshuLab/carrier#', 'AshuLab/carrier#0', 'AshuLab/carrier#-1', 'AshuLab/carrier#1.5', 'AshuLab/carrier#01x', 'carrier#1', 'a/b/c#1', '../b#1', 'a/..#1', ' AshuLab/carrier#1', 'AshuLab/carrier #1', '#1', '12'])(
  'restart with the argument "%s" is a usage error',
  (target) => {
    const parsed = parseCli(['restart', target]);
    expect(parsed.ok).toBe(false);
    expect(parsed.ok === false && parsed.message).toContain('owner/name#N');
  },
);

test('restart without its argument or with a second one is a usage error, and the argument belongs to no other command', () => {
  expect(parseCli(['restart'])).toMatchObject({ ok: false, message: expect.stringContaining('owner/name#N') });
  expect(parseCli(['restart', 'A/a#1', 'B/b#2'])).toMatchObject({ ok: false });
  expect(parseCli(['status', 'A/a#1'])).toEqual({ ok: false, message: 'Unknown command: status A/a#1' });
});

test('restart takes --from ship, review or fix and refuses any other', () => {
  for (const from of ['ship', 'review', 'fix']) expect(parseCli(['restart', 'A/a#1', '--from', from])).toMatchObject({ ok: true, flags: { from } });
  expect(parseCli(['restart', 'A/a#1'])).toMatchObject({ ok: true });
  for (const from of ['merged', '', 'Review', 'lead']) expect(parseCli(['restart', 'A/a#1', '--from', from])).toEqual({ ok: false, message: '--from takes ship, review, fix' });
  expect(usage()).toContain('--from <ship|review|fix>');
});

test('restart takes --extra-rounds as a positive whole number and refuses zero, a negative, a fraction and text, naming the flag', () => {
  expect(parseCli(['restart', 'A/a#1', '--from', 'review', '--extra-rounds', '3'])).toMatchObject({ ok: true, flags: { 'extra-rounds': '3' } });
  for (const rounds of ['0', '-1', '1.5', 'two', '', '007']) expect(parseCli(['restart', 'A/a#1', `--extra-rounds=${rounds}`])).toEqual({ ok: false, message: '--extra-rounds takes a positive whole number' });
  expect(parseCli(['restart', 'A/a#1', '--extra-rounds', '-1'])).toMatchObject({ ok: false, message: expect.stringContaining('--extra-rounds') });
  expect(usage()).toContain('--extra-rounds <K>');
});

test('recover takes one owner/name#N and nothing else', () => {
  expect(parseCli(['recover', 'AshuLab/carrier#12'])).toMatchObject({ ok: true, command: 'recover', target: { repo: 'AshuLab/carrier', issue: 12 } });
  expect(parseCli(['recover'])).toMatchObject({ ok: false, message: expect.stringContaining('recover takes one epic as owner/name#N') });
  expect(parseCli(['recover', 'AshuLab/carrier'])).toMatchObject({ ok: false });
  expect(usage()).toContain('carrier recover <owner/name>#<issue>');
});

test('the usage names restart and its flags', () => {
  expect(usage()).toContain('carrier restart <owner/name>#<issue>');
  expect(usage()).toContain('--author <option>');
});

test('chat takes --list or --stop, and chat-host nothing', () => {
  expect(parseCli(['chat', '--list'])).toMatchObject({ ok: true, command: 'chat', flags: { list: true } });
  expect(parseCli(['chat', '--stop'])).toMatchObject({ ok: true, command: 'chat', flags: { stop: true } });
  expect(parseCli(['chat', '--workspace', '/w', '--agent', 'codex'])).toMatchObject({ ok: true, command: 'chat', flags: { workspace: '/w', agent: 'codex' } });
  expect(parseCli(['chat', '--resume', 'abc'])).toMatchObject({ ok: true, command: 'chat', flags: { resume: 'abc' } });
  expect(parseCli(['chat', '--list', '--archived'])).toMatchObject({ ok: true, flags: { list: true, archived: true } });
  expect(parseCli(['chat', '--archive', 'a'])).toMatchObject({ ok: true, flags: { archive: 'a' } });
  expect(parseCli(['chat', '--unarchive', 'a'])).toMatchObject({ ok: true, flags: { unarchive: 'a' } });
  expect(parseCli(['chat', '--delete', 'a'])).toMatchObject({ ok: true, flags: { delete: 'a' } });
  expect(parseCli(['chat-host'])).toMatchObject({ ok: true, command: 'chat-host' });
});

test('usage takes --json, --refresh, --days, --provider and --source, and the help lists it', () => {
  expect(parseCli(['usage'])).toMatchObject({ ok: true, command: 'usage', flags: {} });
  expect(parseCli(['usage', '--json', '--refresh', '--days', '7', '--provider', 'codex', '--source', 'chat'])).toMatchObject({ ok: true, command: 'usage', flags: { json: true, refresh: true, days: '7', provider: 'codex', source: 'chat' } });
  expect(parseCli(['usage', '--days'])).toMatchObject({ ok: false });
  expect(usage()).toContain('carrier usage ');
});

test('every role the table asks takes its flags, and a slot added to the table adds them with no other option code', () => {
  for (const slot of roleSlots) {
    for (const suffix of roleFlagSuffixes) expect(parseCli(['init', `--${slot}${suffix}`, 'x'])).toMatchObject({ ok: true, command: 'init', flags: { [`${slot}${suffix}`]: 'x' } });
    expect(parseCli(['init', `--${slot}-failover`, 'codex'])).toMatchObject({ ok: true, flags: { [`${slot}-failover`]: ['codex'] } });
  }
  expect(roleSlots).toEqual(['author', 'reviewer', 'lead-reviewer']);
  // no flag of init or restart names an extra reviewer by its place
  for (const flag of ['--reviewer-2', '--reviewer-3-effort', '--reviewer-4-failover']) {
    expect(parseCli(['init', flag, 'x'])).toMatchObject({ ok: false, message: expect.stringContaining(flag) });
    expect(parseCli(['restart', 'A/a#1', flag, 'x'])).toMatchObject({ ok: false, message: expect.stringContaining(flag) });
  }
  expect(usage()).not.toMatch(/reviewer-[234]/);
  expect(parseCli(['init', '--orchestrator-profile', 'gh'])).toMatchObject({ ok: true, flags: { 'orchestrator-profile': 'gh' } });
  expect(parseCli(['init', '--lead-reviewer-effort', 'high', '--lead-reviewer-persona-prompt', 'p'])).toMatchObject({ ok: true, flags: { 'lead-reviewer-effort': 'high', 'lead-reviewer-persona-prompt': 'p' } });
});

test('--<role>-failover repeats and keeps the order given, and a flag no role has is still an error', () => {
  expect(parseCli(['init', '--author-failover', 'codex:gpt-5', '--author-failover', 'claude', '--reviewer-failover', 'claude:llama3:8b'])).toMatchObject({
    ok: true,
    flags: { 'author-failover': ['codex:gpt-5', 'claude'], 'reviewer-failover': ['claude:llama3:8b'] },
  });
  expect(parseCli(['init', '--author-failover'])).toMatchObject({ ok: false });
  expect(parseCli(['init', '--author-fallback', 'codex'])).toMatchObject({ ok: false, message: expect.stringContaining('--author-fallback') });
});

test('restart and recover read the same options as before, --lead among them', () => {
  expect(parseCli(['restart', 'A/a#1', '--author', 'codex', '--reviewer', 'claude', '--lead', 'l', '--from', 'fix', '--extra-rounds', '2'])).toEqual({
    ok: true,
    command: 'restart',
    target: { repo: 'A/a', issue: 1 },
    flags: { author: 'codex', reviewer: 'claude', lead: 'l', from: 'fix', 'extra-rounds': '2' },
  });
  expect(parseCli(['recover', 'A/a#1', '--config', 'x.json'])).toEqual({ ok: true, command: 'recover', target: { repo: 'A/a', issue: 1 }, flags: { config: 'x.json' } });
});

test('the usage shows the role flags as one pattern, not one line per role and flag, and says what --yes picks', () => {
  const text = usage();
  expect(text).toContain('--<role>-failover <account>[:<model>]');
  expect(text).toContain(`for every role: ${roleSlots.join(', ')}`);
  for (const spelled of ['--author-profile', '--reviewer-effort', '--lead-reviewer-provider', '--author-failover']) expect(text).not.toContain(spelled);
  expect(text).toContain('claude for the author and codex for the reviewer when both exist');
  expect(text).not.toContain('one claude option runs both roles');
});
