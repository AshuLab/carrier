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

test('the usage names every command and every init flag', () => {
  for (const word of ['carrier init', 'carrier doctor', 'carrier schema', 'carrier start', '--repo', '--author-profile', '--reviewer-provider', '--out', '--yes', '--config']) expect(usage()).toContain(word);
});

test('start takes the config flag and no other word', () => {
  expect(parseCli(['start', '--config', 'x.json'])).toMatchObject({ ok: true, command: 'start', flags: { config: 'x.json' } });
  expect(parseCli(['start', 'now'])).toEqual({ ok: false, message: 'Unknown command: start now' });
});
