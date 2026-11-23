import { expect, test } from 'vitest';
import type { QuotaSnapshot, QuotaWindow } from '../usage/types.ts';
import { isBack, resumeAtOf } from './resume-at.ts';

const H = 3_600_000;
const win = (id: string, usedPercent: number, resetsAt?: number, group?: string): QuotaWindow => ({ id, label: id, usedPercent, ...(resetsAt !== undefined && { resetsAt }), ...(group !== undefined && { group }) });
const snap = (provider: QuotaSnapshot['provider'], windows: QuotaWindow[], over: Partial<QuotaSnapshot> = {}): QuotaSnapshot => ({ provider, status: 'ok', checkedAt: 0, windows, ...over });
const claude = (...windows: QuotaWindow[]) => ({ model: 'opus', snapshot: snap('claude', windows) });

test('one exhausted window gives its reset time', () => {
  expect(resumeAtOf([claude(win('5h', 100, 5 * H), win('weekly', 40, 90 * H))])).toBe(5 * H);
});

test('several exhausted windows give the latest, a 5-hour and a weekly one both at 100%', () => {
  expect(resumeAtOf([claude(win('5h', 100, 5 * H), win('weekly', 100, 90 * H))])).toBe(90 * H);
});

test('with several options tried it is the earliest of them, and an option that says nothing is left out', () => {
  const codex = { model: 'gpt', snapshot: snap('codex', [win('codex:primary', 100, 2 * H)]) };
  const down = { model: 'gpt', snapshot: snap('codex', [], { status: 'error' }) };
  expect(resumeAtOf([claude(win('5h', 100, 5 * H)), codex, down])).toBe(2 * H);
  expect(resumeAtOf([claude(win('5h', 100, 5 * H)), down])).toBe(5 * H);
});

test('for agy only the windows of the group of the option\'s model count', () => {
  const windows = [win('gemini-5h', 100, 3 * H, 'Gemini Models'), win('3p-5h', 100, 8 * H, 'Claude and GPT models'), win('argon-5h', 100, 6 * H, 'Gemini 4 Argon'), win('dyn', 100, 99 * H, 'Dynamic Pool')];
  const on = (model: string) => resumeAtOf([{ model, snapshot: snap('agy', windows) }]);
  expect(on('gemini-3.8-flash-low')).toBe(3 * H);
  expect(on('gemini-4-argon-high')).toBe(6 * H);
  expect(on('claude-sonnet-4-6')).toBe(8 * H);
  expect(on('gpt-oss-120b')).toBe(8 * H);
  expect(on('mystery-1')).toBeUndefined();
  expect(resumeAtOf([{ model: 'gemini-3.8-flash-low', snapshot: snap('agy', [win('gemini-5h', 40, undefined, 'Gemini Models'), win('3p-5h', 100, 8 * H, 'Claude and GPT models')]) }])).toBeUndefined();
});

test.each([
  ['no window at 100%', claude(win('5h', 99.9, 5 * H))],
  ['no windows, only a credit balance', { model: 'gpt', snapshot: snap('codex', [], { credits: { hasCredits: true, unlimited: false, balance: '12.00' } }) }],
  ['a probe that failed', { model: 'opus', snapshot: snap('claude', [], { status: 'error' }) }],
  ['a probe that was rate limited, even with its last windows', { model: 'opus', snapshot: snap('claude', [win('5h', 100, 5 * H)], { status: 'rate_limited', stale: true }) }],
  ['a provider with no probe', { model: 'm', snapshot: snap('local', [], { status: 'unavailable' }) }],
  ['an exhausted window with no time, only the provider\'s words', claude(win('5h', 100, 5 * H), { ...win('weekly', 100), resetLabel: 'in a few days' })],
])('%s gives no time', (_, tried) => {
  expect(resumeAtOf([tried])).toBeUndefined();
});

test('with no option tried there is no time', () => {
  expect(resumeAtOf([])).toBeUndefined();
});

test('a window is back only when the probe answered, has windows and none is at 100%', () => {
  expect(isBack(claude(win('5h', 30, 5 * H), win('weekly', 99, 90 * H)))).toBe(true);
  expect(isBack(claude(win('5h', 100, 5 * H)))).toBe(false);
  expect(isBack(claude())).toBe(false);
  expect(isBack({ model: 'opus', snapshot: snap('claude', [win('5h', 0)], { status: 'rate_limited' }) })).toBe(false);
});

test('for agy only the group of the option\'s model decides if it is back', () => {
  const windows = [win('gemini-5h', 20, undefined, 'Gemini Models'), win('3p-5h', 100, 8 * H, 'Claude and GPT models')];
  expect(isBack({ model: 'gemini-3.8-flash-low', snapshot: snap('agy', windows) })).toBe(true);
  expect(isBack({ model: 'claude-sonnet-4-6', snapshot: snap('agy', windows) })).toBe(false);
  expect(isBack({ model: 'unknown-model', snapshot: snap('agy', windows) })).toBe(false);
});
