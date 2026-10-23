import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { createServer, type Server } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { Config } from '../../../config/schema.ts';
import { startControlServer } from '../../../control/server.ts';
import type { SessionsReply } from '../../../control/replies.ts';
import type { PanelEpic, PanelSnapshot } from '../../../status/types.ts';
import { statusCommand } from './status.ts';

let root: string;
let closers: (() => void)[];
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'st-')); // short: a socket path holds 103 bytes on macOS
  mkdirSync(join(root, 'orchestrator'));
  closers = [];
});
afterEach(() => {
  for (const close of closers) close();
  rmSync(root, { recursive: true, force: true });
  vi.restoreAllMocks();
});

const epic = (issue: number): PanelEpic => ({
  repo: 'A/a', issue, status: 'running', stage: 'review', round: 1, maxReviews: 5, blockers: 0, stageSince: 0, lastActivityAt: null,
  issueUrl: `https://github.com/A/a/issues/${issue}`, prUrl: null, lastError: null, needsHumanReason: null, slices: null, executionId: null,
});
const snapshot: PanelSnapshot = { now: 2_000_000, slots: { busy: 2, total: 3 }, queue: [], epics: [epic(1), epic(2)], startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false, done: [] };
const stages = (took: number): SessionsReply => ({
  sessions: [{ executionId: 'e', stage: 'ship', role: 'author', round: null, agent: {} as never, status: 'finished', startedAt: 0, finishedAt: took * 60_000, resume: null, result: { outcome: 'completed', summary: 's', verification: null, reason: null } }],
});

const config = () => ({ root }) as Config;
async function printed() {
  const written: string[] = [];
  vi.spyOn(process.stdout, 'write').mockImplementation((text) => (written.push(String(text)), true));
  const code = await statusCommand(config());
  return { code, text: written.join('') };
}

test('status prints the stage lines of a running epic taken over the socket', async () => {
  const asked: string[] = [];
  const controls = {
    poll: () => {}, setPaused: () => {}, logs: () => [],
    sessions: (repo: string, issue: number) => (asked.push(`${repo}#${issue}`), stages(14)),
    events: () => null, epic: () => null, files: () => null, availableRepos: () => Promise.resolve([]), resumeEpic: () => Promise.resolve(),
  };
  closers.push((await startControlServer({ orchestratorDir: join(root, 'orchestrator'), snapshot: () => snapshot, startedAt: 1, controls, stop: async () => {} })).close);
  const { code, text } = await printed();
  expect(code).toBe(0);
  expect(text).toContain('ship ✓ 14m 00s');
  expect(asked).toEqual(['A/a#1', 'A/a#2']);
});

test('a sessions request that errors or answers unknown epic leaves that epic without detail and the others keep theirs; exit stays 0', async () => {
  const controls = {
    poll: () => {}, setPaused: () => {}, logs: () => [],
    sessions: (_repo: string, issue: number) => {
      if (issue === 1) return null; // unknown epic
      return stages(7);
    },
    events: () => null, epic: () => null, files: () => null, availableRepos: () => Promise.resolve([]), resumeEpic: () => Promise.resolve(),
  };
  closers.push((await startControlServer({ orchestratorDir: join(root, 'orchestrator'), snapshot: () => snapshot, startedAt: 1, controls, stop: async () => {} })).close);
  const { code, text } = await printed();
  expect(code).toBe(0);
  expect(text.match(/ship ✓/g)).toHaveLength(1);

  controls.sessions = () => {
    throw new Error('boom'); // answered as an internal error
  };
  const failing = await printed();
  expect([failing.code, failing.text]).toEqual([0, expect.stringContaining('A/a #1')]);
  expect(failing.text).not.toContain('ship ✓');
});

test('against an engine whose hello does not list sessions, no sessions request is sent and the snapshot is drawn alone', async () => {
  const requests: string[] = [];
  const server: Server = createServer((socket) => {
    socket.setEncoding('utf8');
    socket.write(`${JSON.stringify({ event: 'hello', protocol: 1, pid: 1, startedAt: 1, version: '0.0.1', capabilities: [] })}\n`);
    socket.on('data', (chunk: string) => {
      for (const line of chunk.split('\n').filter(Boolean)) {
        const { id, cmd } = JSON.parse(line);
        requests.push(cmd);
        socket.write(`${JSON.stringify(cmd === 'snapshot' ? { id, ok: true, data: snapshot } : { id, ok: false, error: 'unknown command' })}\n`);
      }
    });
  });
  await new Promise<void>((resolve) => server.listen(join(root, 'orchestrator', 'control.sock'), resolve));
  closers.push(() => server.close());
  const { code, text } = await printed();
  expect(code).toBe(0);
  expect(text).toContain('A/a #1');
  expect(requests).toEqual(['snapshot']);
});

test('status asks for the stages of the epics that need a person and the ones ready for test too', async () => {
  const asked: string[] = [];
  const controls = {
    poll: () => {}, setPaused: () => {}, logs: () => [],
    sessions: (repo: string, issue: number) => (asked.push(`${repo}#${issue}`), stages(14)),
    events: () => null, epic: () => null, files: () => null, availableRepos: () => Promise.resolve([]), resumeEpic: () => Promise.resolve(),
  };
  const more: PanelSnapshot = {
    ...snapshot,
    epics: [{ ...epic(1), status: 'needs_human', needsHumanReason: 'stuck' }],
    done: [{ repo: 'A/a', issue: 3, title: null, labels: [], prNumber: 9, finishedAt: 1_000_000, executionId: 'e' }],
  };
  closers.push((await startControlServer({ orchestratorDir: join(root, 'orchestrator'), snapshot: () => more, startedAt: 1, controls, stop: async () => {} })).close);
  const { code, text } = await printed();
  expect(code).toBe(0);
  expect(asked).toEqual(['A/a#1', 'A/a#3']);
  expect(text.match(/ship ✓ 14m 00s/g)).toHaveLength(2);
});
