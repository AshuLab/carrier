import { existsSync, mkdirSync, readdirSync, realpathSync, renameSync, rmSync, statSync, utimesSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { chatPlacesOf } from '../config/places.ts';

// The app copies a dropped file to `chat/pending/<id>/<name>` and lists its path in a block after the message (Attachments.swift).
// When the message is sent the host moves each copy into the session, `chat/sessions/<session>/attachments/<id>/<name>`,
// so deleting the session takes its files with it; what is never sent is swept from pending after a day.

const log = createScopedLogger('chat');
const heading = 'Attached files:';
const DAY_MS = 24 * 60 * 60 * 1000;
const safeId = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;

/** The session's own folder; its id comes from SQLite but ends up in a path, so only a plain id is accepted. */
export function sessionFolder(sessionId: string, folder?: string) {
  if (!safeId.test(sessionId)) throw new Error(`invalid session id "${sessionId}"`);
  return join(chatPlacesOf(folder).sessions, sessionId);
}

/**
 * The message with every attached copy still in pending moved into the session and its path rewritten; any other path is left as it is.
 * A copy already moved (the same message sent again) is found in the session and rewritten too.
 */
export function claimAttachments(text: string, sessionId: string, folder?: string): string {
  const marker = `\n\n${heading}\n`;
  const at = text.lastIndexOf(marker);
  const start = at >= 0 ? at + marker.length : text.startsWith(`${heading}\n`) ? heading.length + 1 : -1;
  if (start < 0) return text;
  const lines = text.slice(start).split('\n');
  if (lines.every((line) => line.startsWith('- /')) === false) return text;
  const pending = realOrUndefined(chatPlacesOf(folder).pending);
  if (pending === undefined) return text;
  const into = join(sessionFolder(sessionId, folder), 'attachments');
  const claimed = lines.map((line) => {
    const path = line.slice(2);
    const copy = dirname(path);
    const id = basename(copy);
    // compared by real path: the app writes the Carrier folder as it was given, which may differ in form from the host's
    if (realOrUndefined(dirname(copy)) !== pending || !safeId.test(id)) return line;
    const target = join(into, id);
    try {
      // only a real folder inside pending moves: a symlink out of it is not Carrier's copy
      if (existsSync(copy) && realpathSync(copy) === join(pending, id)) {
        mkdirSync(into, { recursive: true });
        renameSync(copy, target);
      }
    } catch (error) {
      log.error('an attached file could not be moved into its session', error, { sessionId });
      return line;
    }
    return existsSync(join(target, basename(path))) ? `- ${join(target, basename(path))}` : line;
  });
  return text.slice(0, start) + claimed.join('\n');
}

/**
 * Undoes the claims of a session cancelled before its first message reached the agent: its copies go back to pending, with a new day
 * before the sweep, and the text points at them there again, so the draft it is put back in keeps its files.
 */
export function releaseAttachments(text: string, sessionId: string, folder?: string): string {
  const from = join(sessionFolder(sessionId, folder), 'attachments');
  const pending = chatPlacesOf(folder).pending;
  let ids: string[];
  try {
    ids = readdirSync(from);
  } catch {
    return text; // nothing was attached
  }
  let released = text;
  for (const id of ids) {
    try {
      mkdirSync(pending, { recursive: true });
      renameSync(join(from, id), join(pending, id));
      utimesSync(join(pending, id), new Date(), new Date());
      released = released.replaceAll(`${join(from, id)}/`, `${join(pending, id)}/`);
    } catch (error) {
      log.error('an attached file could not be put back in pending', error, { sessionId });
    }
  }
  return released;
}

/** Removes from pending the copies dropped more than a day before `now` and never sent. */
export function sweepPending(now: number, folder?: string) {
  const pending = chatPlacesOf(folder).pending;
  let entries: string[];
  try {
    entries = readdirSync(pending);
  } catch {
    return; // nothing was ever dropped
  }
  for (const entry of entries) {
    const path = join(pending, entry);
    try {
      if (now - statSync(path).mtimeMs > DAY_MS) rmSync(path, { recursive: true, force: true });
    } catch (error) {
      log.error('an unsent attachment could not be swept', error, { path });
    }
  }
}

const realOrUndefined = (path: string) => {
  try {
    return realpathSync(path);
  } catch {
    return undefined;
  }
};
