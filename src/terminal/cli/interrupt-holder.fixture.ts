// Child process for interrupt.test.ts: the real startup (startCarrier: lock, logging, SQLite, engine, panel, signal handlers)
// with fake GitHub, workspaces and runner. Two epics start, each run hangs with its session reported, and it
// prints 'ready' once both sessions are saved. Every GitHub write goes to writes.log, after the marker of the signal
// that arrived (or of 'shutdown', each time the engine is asked to stop); every launched task goes to tasks.log. With a third argument 'hang' the runner never finishes
// stopping, and the fourth is the shutdown's time limit in ms.
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
const hangOnStop = process.argv[3] === 'hang';
const timeoutMs = process.argv[4] ? Number(process.argv[4]) : undefined;
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
  providers: { claude: { harness: 'claude' } },
  agents: {
    author: { profile: 'a', provider: 'claude', model: 'm' },
    reviewer: { profile: 'b', provider: 'claude', model: 'm' },
  },
  limits: { maxConcurrentEpics: 2 },
});
if (!loaded.ok) throw new Error(JSON.stringify(loaded.errors));

const github = new RecordingGitHub();
github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 2, title: '' }, { issue: 3, title: '' }] };
const runner = new FakeAgentRunner();
if (hangOnStop) {
  const run = runner.run.bind(runner);
  runner.run = (task) => ({ ...run(task), stop: () => new Promise<void>(() => {}) });
}
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
    for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, () => log(signal)); // registered first: runs before the shutdown handler
    // 'shutdown' marks every time the engine is asked to stop, whatever started it (a signal or the socket)
    return stopOnSigint({ ...target, engine: { shutdown: () => (log('shutdown'), target.engine.shutdown()) } }, { timeoutMs });
  },
});

const sessions = setInterval(() => {
  if (app.db.select().from(executions).all().filter((e) => e.sessionId).length >= 2) {
    clearInterval(sessions);
    process.stdout.write('ready\n');
  }
}, 10);
