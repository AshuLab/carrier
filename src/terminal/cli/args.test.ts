import { expect, test } from 'vitest';
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
  for (const word of ['carrier init', 'carrier doctor', 'carrier schema', 'carrier start', 'carrier status', 'stop', 'pause', 'resume', 'check', 'carrier chat ', 'carrier chat-host', '--repo', '--author-profile', '--reviewer-provider', '--out', '--yes', '--config', '--json']) expect(usage()).toContain(word);
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
