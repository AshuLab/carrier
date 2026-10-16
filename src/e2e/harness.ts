import { execFileSync, spawn, type ChildProcess } from 'node:child_process';
import { appendFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, openSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';

/**
 * Helpers of the end-to-end test (carrier.integration.test.ts). Nothing here runs by itself.
 * Seeding and counting go through Diego's own `gh` login on the disposable sandbox repo; Carrier and the agents
 * act through the Forge bots named in the environment.
 */

export const mainTs = join(import.meta.dirname, '..', 'cli', 'main.ts');

export interface E2eEnv {
  repo: string;
  authorAgent: string;
  reviewerAgent: string;
  author: { provider: 'claude' | 'codex'; model: string };
  reviewer: { provider: 'claude' | 'codex'; model: string };
  /** Folder with the Solve skills (`.../solve/<version>/skills`), copied into the sandbox's `.agents/skills` so Codex finds them. */
  skillsDir?: string;
  scenarios: string[];
}

const providerModel = (value: string, fallback: string): E2eEnv['author'] => {
  const [provider, ...model] = (value || fallback).split(':');
  if ((provider !== 'claude' && provider !== 'codex') || model.length === 0) throw new Error(`expected <claude|codex>:<model>, got "${value}"`);
  return { provider, model: model.join(':') };
};

export function readEnv(env: NodeJS.ProcessEnv = process.env): E2eEnv | null {
  const { CARRIER_E2E_REPO: repo, CARRIER_E2E_AUTHOR_AGENT: authorAgent, CARRIER_E2E_REVIEWER_AGENT: reviewerAgent } = env;
  if (!repo || !authorAgent || !reviewerAgent) return null;
  if (!/^[\w.-]+\/[\w.-]*sandbox$/.test(repo)) throw new Error(`CARRIER_E2E_REPO must be a disposable repo whose name ends in "sandbox", got "${repo}"`);
  return {
    repo,
    authorAgent,
    reviewerAgent,
    author: providerModel(env.CARRIER_E2E_AUTHOR ?? '', 'claude:sonnet'),
    reviewer: providerModel(env.CARRIER_E2E_REVIEWER ?? '', 'codex:gpt-5.6-luna'),
    skillsDir: env.CARRIER_E2E_SKILLS_DIR,
    scenarios: (env.CARRIER_E2E_SCENARIOS ?? 'a,b,c,d,e').split(','),
  };
}

export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export async function waitFor<T>(what: string, check: () => T | undefined | false | null | Promise<T | undefined | false | null>, timeoutMs: number, everyMs = 2000): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() > deadline) throw new Error(`timed out after ${Math.round(timeoutMs / 1000)} s waiting for ${what}`);
    await sleep(everyMs);
  }
}

const run = (bin: string, args: string[], opts: { cwd?: string; input?: string } = {}) =>
  execFileSync(bin, args, { cwd: opts.cwd, input: opts.input, encoding: 'utf8', timeout: 120_000, stdio: ['pipe', 'pipe', 'pipe'] }).trim();

export class Evidence {
  readonly file: string;
  constructor(root: string) {
    this.file = join(root, 'e2e-evidence.log');
  }
  log(line: string) {
    const text = `${new Date().toISOString()} ${line}`;
    console.log(text);
    appendFileSync(this.file, `${text}\n`);
  }
}

export interface SliceSpec {
  title: string;
  body: string;
}

export interface EpicSpec {
  /** Also the title of the epic issue: the branch namespace and the worktree folder come from its slug. */
  title: string;
  problem: string;
  solution: string;
  slices: SliceSpec[];
}

export const slug = (title: string) => title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

/** The sandbox repo through Diego's `gh` login: seeding and counting only. */
export class Sandbox {
  readonly repo: string;
  readonly seed: string;

  constructor(repo: string, seedDir: string) {
    this.repo = repo;
    this.seed = seedDir;
  }

  gh(args: string[]) {
    return run('gh', args);
  }

  api<T = unknown>(path: string, paginate = false): T {
    const out = this.gh(['api', ...(paginate ? ['--paginate', '--slurp'] : []), path]);
    const parsed = JSON.parse(out) as unknown;
    return (paginate ? (parsed as unknown[]).flat() : parsed) as T;
  }

  git(args: string[]) {
    return run('git', args, { cwd: this.seed });
  }

  clone() {
    run('gh', ['repo', 'clone', this.repo, this.seed, '--', '-q']);
  }

  commitAndPush(message: string) {
    this.git(['add', '-A']);
    if (this.git(['status', '--porcelain']) === '') return;
    this.git(['commit', '-q', '-m', message]);
    this.git(['pull', '-q', '--rebase', 'origin', 'main']);
    this.git(['push', '-q', 'origin', 'HEAD:main']);
  }

  /** Points Solve's worktrees at this run's root (the repo's solve.md is versioned and absolute) and gives Codex the review skills. */
  prepare(root: string, skillsDir?: string) {
    this.git(['pull', '-q', '--rebase', 'origin', 'main']);
    const solveMd = join(this.seed, 'docs', 'agents', 'solve.md');
    const text = readFileSync(solveMd, 'utf8').replace(/^- \*\*path\*\* - .*$/m, `- **path** - \`${root}/worktrees/<repo>/<feature>/\``);
    writeFileSync(solveMd, text);
    if (skillsDir) {
      for (const skill of ['code-review', 'code-post']) cpSync(join(skillsDir, skill), join(this.seed, '.agents', 'skills', skill), { recursive: true });
    }
    this.commitAndPush('chore: point the solve worktrees at the e2e root');
  }

  /** Spec on main first (a managed clone only sees what is pushed), then the epic and its slices, each blocked by the previous one. Not marked ready. */
  seedEpic(epic: EpicSpec): { epic: number; slices: number[]; feature: string } {
    const feature = slug(epic.title);
    const spec = `# ${epic.title}\n\nStatus: spec\n\n## Problem\n${epic.problem}\n\n## Solution\n${epic.solution}\n\n## Out of scope\nAnything not listed above.\n`;
    mkdirSync(join(this.seed, 'docs', 'specs'), { recursive: true });
    writeFileSync(join(this.seed, 'docs', 'specs', `${feature}.md`), spec);
    this.commitAndPush(`docs: spec for ${feature}`);
    const create = (args: string[]) => {
      const url = this.gh(['issue', 'create', '--repo', this.repo, ...args]);
      return Number(url.split('/').pop());
    };
    const body = join(mkdtempSync(join(tmpdir(), 'carrier-e2e-body-')), 'body.md');
    writeFileSync(body, spec.split('\n').slice(4).join('\n'));
    const number = create(['--title', epic.title, '--body-file', body, '--label', 'solve:epic']);
    const slices: number[] = [];
    epic.slices.forEach((slice, index) => {
      writeFileSync(body, `# ${String(index + 1).padStart(3, '0')} - ${slice.title}\n\n${slice.body}\n\n## Blocked by\n${index === 0 ? 'nothing' : `#${slices[index - 1]}`}\n`);
      slices.push(create(['--title', slice.title, '--body-file', body, '--label', 'solve:ticket,solve:refined', '--parent', String(number), ...(index === 0 ? [] : ['--blocked-by', String(slices[index - 1])])]));
    });
    return { epic: number, slices, feature };
  }

  markReady(epic: number) {
    this.gh(['issue', 'edit', String(epic), '--repo', this.repo, '--add-label', 'solve:epic:ready']);
  }

  labels(issue: number): string[] {
    return this.api<{ labels: { name: string }[] }>(`repos/${this.repo}/issues/${issue}`).labels.map((l) => l.name).sort();
  }

  /** What exists on GitHub for one epic and its feature namespace: the numbers the duplicate checks compare before and after. */
  count(epic: number, feature: string) {
    const pulls = this.api<{ number: number; title: string; head: { ref: string }; body: string | null }[]>(`repos/${this.repo}/pulls?state=all&per_page=100`, true).filter((p) => p.head.ref.startsWith(`feat/${feature}/`));
    const epicComments = this.api<{ id: number; body: string; user: { login: string } }[]>(`repos/${this.repo}/issues/${epic}/comments?per_page=100`, true);
    let prComments = 0;
    let reviewComments = 0;
    let reviews = 0;
    for (const p of pulls) {
      prComments += this.api<unknown[]>(`repos/${this.repo}/issues/${p.number}/comments?per_page=100`, true).length;
      reviewComments += this.api<unknown[]>(`repos/${this.repo}/pulls/${p.number}/comments?per_page=100`, true).length;
      reviews += this.api<unknown[]>(`repos/${this.repo}/pulls/${p.number}/reviews?per_page=100`, true).length;
    }
    // Commits of the feature's branches, unique by SHA, as the repo sees them (main excluded).
    const commits = new Map<string, string>();
    const branches = this.api<{ name: string }[]>(`repos/${this.repo}/branches?per_page=100`, true).filter((b) => b.name.startsWith(`feat/${feature}/`));
    for (const b of branches) for (const [sha, message] of this.compareCommits(b.name)) commits.set(sha, message);
    return {
      prs: pulls.length,
      prHeads: pulls.map((p) => p.head.ref).sort(),
      integrationPrs: pulls.filter((p) => /\bcloses #(\d+)/i.exec(p.body ?? '')?.[1] === String(epic)).map((p) => p.number),
      epicComments: epicComments.length,
      epicCommentBodies: epicComments.map((c) => c.body.slice(0, 200)),
      prComments,
      reviewComments,
      reviews,
      commits: commits.size,
      commitMessages: [...commits.values()].sort(),
      branches: branches.map((b) => b.name).sort(),
    };
  }

  private compareCommits(branch: string): [string, string][] {
    const { commits } = this.api<{ commits: { sha: string; commit: { message: string } }[] }>(`repos/${this.repo}/compare/main...${encodeURIComponent(branch)}`);
    return commits.map((c) => [c.sha, c.commit.message.split('\n')[0]!]);
  }

  /** Files a PR changes. */
  prFiles(pr: number): string[] {
    return this.api<{ filename: string }[]>(`repos/${this.repo}/pulls/${pr}/files?per_page=100`, true).map((f) => f.filename).sort();
  }
}

/** The shared root of a run: a real temp dir (macOS /var is a symlink, and git prints the real path). */
export const makeRoot = () => realpathSync(mkdtempSync(join(tmpdir(), 'carrier-e2e-')));

export interface RunConfig {
  root: string;
  repo: string;
  authorAgent: string;
  reviewerAgent: string;
  author: E2eEnv['author'];
  reviewer: E2eEnv['reviewer'];
}

export function writeConfig(c: RunConfig, file: string) {
  const config = {
    root: c.root,
    // Any positive number is allowed; 12 s keeps the wait between a result and the next GitHub call short.
    pollIntervalMinutes: 0.2,
    logLevel: 'debug',
    repos: [{ name: c.repo }],
    profiles: { author: { kind: 'forge', agent: c.authorAgent }, reviewer: { kind: 'forge', agent: c.reviewerAgent } },
    orchestratorProfile: 'author',
    agents: { author: { profile: 'author', ...c.author }, reviewer: { profile: 'reviewer', ...c.reviewer } },
    limits: { maxConcurrentEpics: 2, maxReviews: 2, maxExecutionRetries: 2, maxExecutionHours: 1, githubCallTimeoutSeconds: 60 },
  };
  writeFileSync(file, `${JSON.stringify(config, null, 2)}\n`);
}

export class CarrierProcess {
  readonly out: string;
  private child: ChildProcess | undefined;
  exit: { code: number | null; signal: NodeJS.Signals | null } | undefined;

  constructor(
    private readonly config: string,
    logFile: string,
  ) {
    this.out = logFile;
  }

  get pid() {
    return this.child?.pid;
  }

  start() {
    const fd = openSync(this.out, 'a');
    // From another folder on purpose: carrier must not depend on the cwd. Not detached: agents lead their own groups, carrier does not need to.
    this.exit = undefined;
    this.child = spawn(process.execPath, [mainTs, '--config', this.config], { cwd: tmpdir(), stdio: ['ignore', fd, fd] });
    this.child.on('exit', (code, signal) => (this.exit = { code, signal }));
    return this;
  }

  signal(sig: NodeJS.Signals) {
    if (this.child?.pid && !this.exit) process.kill(this.child.pid, sig);
  }

  async stopped(timeoutMs: number) {
    await waitFor('carrier to exit', () => this.exit, timeoutMs, 200);
    return this.exit!;
  }
}

/** Read-only view of carrier's SQLite (WAL-safe while carrier writes). */
export function openDb(root: string) {
  const file = join(root, 'orchestrator', 'carrier.db');
  return existsSync(file) ? new Database(file, { readonly: true }) : null;
}

export interface EpicRow {
  id: number;
  issue: number;
  status: string;
  stage: string | null;
  round: number | null;
  prNumber: number | null;
  workspace: string | null;
  needsHumanReason: string | null;
  lastError: string | null;
}
export interface ExecRow {
  executionId: string;
  stage: string;
  status: string;
  sessionId: string | null;
  error: string | null;
  resultPath: string;
}

export function dbEpic(root: string, issue: number): EpicRow | undefined {
  const db = openDb(root);
  try {
    return db?.prepare('select id, issue, status, stage, round, prNumber, workspace, needsHumanReason, lastError from epics where issue = ?').get(issue) as EpicRow | undefined;
  } finally {
    db?.close();
  }
}

export function dbExecutions(root: string, issue: number): ExecRow[] {
  const db = openDb(root);
  try {
    return (db?.prepare('select e.executionId, e.stage, e.status, e.sessionId, e.error, e.resultPath from executions e join epics p on p.id = e.epicId where p.issue = ? order by e.rowid').all(issue) ?? []) as ExecRow[];
  } finally {
    db?.close();
  }
}

export function dbEvents(root: string, issue: number): { type: string; data: string }[] {
  const db = openDb(root);
  try {
    return (db?.prepare('select ev.type, ev.data from epic_events ev join epics p on p.id = ev.epicId where p.issue = ? order by ev.id').all(issue) ?? []) as { type: string; data: string }[];
  } finally {
    db?.close();
  }
}

export function dbResultCount(root: string, executionId: string): number {
  const db = openDb(root);
  try {
    return (db?.prepare('select count(*) as n from caller_results where executionId = ?').get(executionId) as { n: number }).n;
  } finally {
    db?.close();
  }
}

/** Live agent processes carrying carrier's execution marker, found as carrier itself finds them. */
export function markedProcesses(): { pid: number; command: string }[] {
  const out = run('ps', ['-axo', 'pid=,command=']);
  return out
    .split('\n')
    .filter((l) => /carrier-exec-/.test(l) && !/\bps -axo\b/.test(l))
    .map((l) => ({ pid: Number(l.trim().split(/\s+/)[0]), command: l.trim().split(/\s+/).slice(1).join(' ').slice(0, 160) }));
}

/** Process groups of the agents (they lead their own), then whatever is left: last resort so no test run leaves agents behind. */
export function killMarked() {
  for (const { pid } of markedProcesses()) {
    for (const target of [-pid, pid]) {
      try {
        process.kill(target, 'SIGKILL');
      } catch {
        // already gone
      }
    }
  }
}

export const listDir = (dir: string) => (existsSync(dir) ? readdirSync(dir) : []);

export const resultFile = (root: string, executionId: string) => join(root, 'orchestrator', 'results', `${executionId}.json`);

/** Any process whose command line mentions the run's root: what an agent leaves behind after being stopped (Codex orphans its command process). */
export function stragglers(root: string): { pid: number; command: string }[] {
  const out = run('ps', ['-axo', 'pid=,command=']);
  return out
    .split('\n')
    .filter((l) => l.includes(root) && !/\bps -axo\b/.test(l) && !l.includes('vitest'))
    .map((l) => ({ pid: Number(l.trim().split(/\s+/)[0]), command: l.trim().split(/\s+/).slice(1).join(' ').slice(0, 160) }));
}

export function killStragglers(root: string) {
  for (const { pid } of stragglers(root)) {
    try {
      process.kill(pid, 'SIGKILL');
    } catch {
      // already gone
    }
  }
}

/** Where Claude keeps a session, by id; null when it is not there. */
export function claudeSessionFile(sessionId: string): string | null {
  const projects = join(process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), '.claude'), 'projects');
  for (const dir of listDir(projects)) {
    const file = join(projects, dir, `${sessionId}.jsonl`);
    if (existsSync(file)) return file;
  }
  return null;
}
