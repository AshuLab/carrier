// Child process for interrupt.test.ts: a real carrier process (lock, SQLite, engine, SIGINT handler)
// with fake GitHub and runner. Two epics start, each run hangs with its session reported, and it
// prints 'ready' once both sessions are saved. Every GitHub write goes to writes.log, after a SIGINT marker.
import { appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { FakeAgentRunner, FakeWorkspaces } from '../execution/fake.ts';
import { createEngine } from '../orchestration/engine.ts';
import { realClock } from '../orchestration/clock.ts';
import { FakeGitHub } from '../orchestration/fake.ts';
import { openDatabase } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { acquireLock } from '../storage/lock.ts';
import { stopOnSigint } from './interrupt.ts';

const root = process.argv[2]!;
const orchestratorDir = join(root, 'orchestrator');
const writes = join(root, 'writes.log');
const log = (line: string) => appendFileSync(writes, `${line}\n`);

class RecordingGitHub extends FakeGitHub {
  override async setLabels(repo: string, issue: number, change: { add: string[]; remove: string[] }) {
    log(`setLabels ${repo}#${issue}`);
    return super.setLabels(repo, issue, change);
  }

  override async createLabel(repo: string, name: string) {
    log(`createLabel ${repo}:${name}`);
    return super.createLabel(repo, name);
  }
}

const lock = acquireLock(orchestratorDir);
if (!lock.ok) process.exit(1);
const db = openDatabase(join(orchestratorDir, 'carrier.db'));
const github = new RecordingGitHub();
github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 2, title: '' }, { issue: 3, title: '' }] };
const runner = new FakeAgentRunner();
runner.behavior = (task) => ({ sessionId: `s-${task.epic}`, exit: 'hang' });
const agents = {
  author: { profile: 'a', provider: 'claude' as const, model: 'm' },
  reviewer: { profile: 'b', provider: 'codex' as const, model: 'm' },
};
const engine = createEngine({
  db, github, clock: realClock, repos: [{ name: 'AshuLab/a', agents }], pollIntervalMs: 20, maxConcurrentEpics: 2,
  maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews: 5, runner, workspaces: new FakeWorkspaces(), root,
});

process.on('SIGINT', () => log('SIGINT')); // registered first: runs before the shutdown handler
stopOnSigint({ engine, close: () => (db.$client.close(), lock.release()) });
await engine.start();

const sessions = setInterval(() => {
  if (db.select().from(executions).all().filter((e) => e.sessionId).length === 2) {
    clearInterval(sessions);
    console.log('ready');
  }
}, 10);
