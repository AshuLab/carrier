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
  for (const word of ['carrier init', 'carrier doctor', 'carrier schema', 'carrier start', 'carrier status', 'stop', 'pause', 'resume', 'check', 'carrier chat ', 'carrier chat-host', '--repo', '--author-profile', '--reviewer-provider', '--out', '--yes', '--config']) expect(usage()).toContain(word);
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

test('chat takes --list or --stop, and chat-host the config', () => {
  expect(parseCli(['chat', '--list'])).toMatchObject({ ok: true, command: 'chat', flags: { list: true } });
  expect(parseCli(['chat', '--stop', '--config', 'x.json'])).toMatchObject({ ok: true, command: 'chat', flags: { stop: true, config: 'x.json' } });
  expect(parseCli(['chat', '--workspace', '/w', '--agent', 'codex'])).toMatchObject({ ok: true, command: 'chat', flags: { workspace: '/w', agent: 'codex' } });
  expect(parseCli(['chat', '--resume', 'abc'])).toMatchObject({ ok: true, command: 'chat', flags: { resume: 'abc' } });
  expect(parseCli(['chat', '--list', '--archived'])).toMatchObject({ ok: true, flags: { list: true, archived: true } });
  expect(parseCli(['chat', '--archive', 'a'])).toMatchObject({ ok: true, flags: { archive: 'a' } });
  expect(parseCli(['chat', '--unarchive', 'a'])).toMatchObject({ ok: true, flags: { unarchive: 'a' } });
  expect(parseCli(['chat', '--delete', 'a'])).toMatchObject({ ok: true, flags: { delete: 'a' } });
  expect(parseCli(['chat-host', '--config', 'x.json'])).toMatchObject({ ok: true, command: 'chat-host', flags: { config: 'x.json' } });
});
