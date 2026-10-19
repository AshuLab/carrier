// Child process for interrupt.test.ts: the real startup (startCarrier: lock, logging, SQLite, engine, panel, SIGINT handler)
// with fake GitHub, workspaces and runner. Two epics start, each run hangs with its session reported, and it
// prints 'ready' once both sessions are saved. Every GitHub write goes to writes.log, after a SIGINT marker;
// every launched task goes to tasks.log.
import { appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { defaults, loadConfig } from '../../config/load.ts';
import { FakeAgentRunner, FakeWorkspaces } from '../../execution/fake.ts';
import { FakeGitHub } from '../../orchestration/fake.ts';
import type { LabelStyle } from '../../orchestration/github.ts';
import { executions } from '../../storage/executions.ts';
import { startCarrier } from './compose.ts';
import { stopOnSigint } from './interrupt.ts';

const root = process.argv[2]!;
const writes = join(root, 'writes.log');
const log = (line: string) => appendFileSync(writes, `${line}\n`);

class RecordingGitHub extends FakeGitHub {
  override async setLabels(repo: string, issue: number, change: { add: string[]; remove: string[] }) {
    log(`setLabels ${repo}#${issue}`);
    return super.setLabels(repo, issue, change);
  }

  override async createLabel(repo: string, name: string, style: LabelStyle) {
    log(`createLabel ${repo}:${name}`);
    return super.createLabel(repo, name, style);
  }
}

const loaded = loadConfig(defaults, {
  root,
  pollIntervalMinutes: 20 / 60_000, // 20 ms
  repos: [{ name: 'AshuLab/a' }],
  profiles: { a: { kind: 'gh' }, b: { kind: 'gh' } },
  orchestratorProfile: 'a',
  agents: {
    author: { profile: 'a', harness: 'claude', model: 'm' },
    reviewer: { profile: 'b', harness: 'codex', model: 'm' },
  },
  limits: { maxConcurrentEpics: 2 },
});
if (!loaded.ok) throw new Error(JSON.stringify(loaded.errors));

const github = new RecordingGitHub();
github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 2, title: '' }, { issue: 3, title: '' }] };
const runner = new FakeAgentRunner();
runner.behavior = (task) => {
  appendFileSync(join(root, 'tasks.log'), `${task.epic}:${task.resumeSession ?? '-'}:${task.context.verifyStateFirst ?? '-'}\n`);
  return { sessionId: `s-${task.epic}`, exit: 'hang' };
};

const app = await startCarrier(loaded.config, {
  makeGitHub: () => github,
  makeWorkspaces: () => new FakeWorkspaces(),
  makeRunner: () => runner,
  panelOut: { write: () => {} }, // the terminal only gets 'ready'
  onSigint: (target) => {
    process.on('SIGINT', () => log('SIGINT')); // registered first: runs before the shutdown handler
    stopOnSigint(target);
  },
});

const sessions = setInterval(() => {
  if (app.db.select().from(executions).all().filter((e) => e.sessionId).length >= 2) {
    clearInterval(sessions);
    process.stdout.write('ready\n');
  }
}, 10);
