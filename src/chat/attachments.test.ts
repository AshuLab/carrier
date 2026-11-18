import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { chatPlacesOf } from '../config/places.ts';
import { claimAttachments, sessionFolder, sweepPending } from './attachments.ts';

let folder: string;
beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), 'carrier-attach-'));
});
afterEach(() => rmSync(folder, { recursive: true, force: true }));

const dropped = (id: string, name: string) => {
  const path = join(chatPlacesOf(folder).pending, id, name);
  mkdirSync(join(chatPlacesOf(folder).pending, id), { recursive: true });
  writeFileSync(path, 'content');
  return path;
};
const inSession = (session: string, id: string, name: string) => join(sessionFolder(session, folder), 'attachments', id, name);

test('a sent copy moves from pending into the session and the message points at it; other paths stay', () => {
  const path = dropped('A1', 'shot.png');
  const text = `look at this\n\nAttached files:\n- ${path}\n- /Users/me/project/`;
  expect(claimAttachments(text, 's1', folder)).toBe(`look at this\n\nAttached files:\n- ${inSession('s1', 'A1', 'shot.png')}\n- /Users/me/project/`);
  expect(readFileSync(inSession('s1', 'A1', 'shot.png'), 'utf8')).toBe('content');
  expect(existsSync(join(chatPlacesOf(folder).pending, 'A1'))).toBe(false);
});

test('sending the same message again finds the copy already in the session', () => {
  const text = `Attached files:\n- ${dropped('A1', 'a.txt')}`;
  const first = claimAttachments(text, 's1', folder);
  expect(claimAttachments(text, 's1', folder)).toBe(first);
});

test('a message without a whole block of paths is left as it is', () => {
  const path = dropped('A1', 'a.txt');
  for (const text of ['hello', `hello\n\nAttached files:\n- ${path}\nnot a path`]) expect(claimAttachments(text, 's1', folder)).toBe(text);
  expect(existsSync(path)).toBe(true);
});

test('a copy is claimed whatever form of the Carrier folder its path was written with', () => {
  dropped('A1', 'a.txt');
  const alias = join(mkdtempSync(join(tmpdir(), 'carrier-alias-')), 'home');
  symlinkSync(folder, alias);
  const text = `Attached files:\n- ${join(alias, 'chat', 'pending', 'A1', 'a.txt')}`;
  expect(claimAttachments(text, 's1', folder)).toBe(`Attached files:\n- ${inSession('s1', 'A1', 'a.txt')}`);
  rmSync(dirname(alias), { recursive: true });
});

test('a symlink in pending that leads out of it is not moved', () => {
  const outside = join(folder, 'outside');
  mkdirSync(outside);
  writeFileSync(join(outside, 'secret.txt'), 'precious');
  mkdirSync(chatPlacesOf(folder).pending, { recursive: true });
  symlinkSync(outside, join(chatPlacesOf(folder).pending, 'L1'));
  const text = `Attached files:\n- ${join(chatPlacesOf(folder).pending, 'L1', 'secret.txt')}`;
  expect(claimAttachments(text, 's1', folder)).toBe(text);
  expect(existsSync(join(outside, 'secret.txt'))).toBe(true);
});

test('a session id that is not plain is refused before it becomes a path', () => {
  expect(() => sessionFolder('../x', folder)).toThrow();
});

test('copies left in pending more than a day are swept, newer ones stay', () => {
  const old = dropped('OLD', 'a.txt');
  const recent = dropped('NEW', 'b.txt');
  const now = Date.now();
  const twoDaysAgo = (now - 2 * 24 * 60 * 60 * 1000) / 1000;
  utimesSync(join(chatPlacesOf(folder).pending, 'OLD'), twoDaysAgo, twoDaysAgo);
  sweepPending(now, folder);
  expect([existsSync(old), existsSync(recent)]).toEqual([false, true]);
});
