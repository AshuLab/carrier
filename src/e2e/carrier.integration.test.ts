import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';
import {
  CarrierProcess,
  Evidence,
  Sandbox,
  dbEpic,
  dbExecutions,
  killMarked,
  makeRoot,
  markedProcesses,
  readEnv,
  waitFor,
  writeConfig,
  type EpicSpec,
} from './harness.ts';

/**
 * The real thing: carrier (the CLI, as a process), Claude and Codex, Forge and Solve, against a disposable repo.
 * It takes tens of minutes and spends money, so it never runs in `pnpm test` and only runs here when these are set:
 *
 *   CARRIER_E2E_REPO=AshuLab/carrier-sandbox      a disposable repo whose name ends in "sandbox" (docs/research/sandbox-repo.md)
 *   CARRIER_E2E_AUTHOR_AGENT=artanis-agent         Forge agent for the author (also the orchestrator)
 *   CARRIER_E2E_REVIEWER_AGENT=tassadar-agent      Forge agent for the reviewer: must differ from the author's
 *
 * Optional:
 *   CARRIER_E2E_AUTHOR=claude:sonnet               <claude|codex>:<model>, default as shown
 *   CARRIER_E2E_REVIEWER=codex:gpt-6-luna          idem
 *   CARRIER_E2E_SKILLS_DIR=<solve plugin>/skills   copied into the sandbox's .agents/skills so a Codex reviewer finds code-review and code-post
 *   CARRIER_E2E_SCENARIOS=a,b,c,d,e               which of the Definition of done scenarios to run (default all)
 *
 * Needs `gh` logged in with write access to the repo (it seeds epics and counts things), `agent-forge` with both agents
 * installed on the repo's owner, and the `claude` and `codex` CLIs logged in. The test writes to the repo (a spec and the
 * solve.md path on main, issues, branches, PRs) and leaves everything there as evidence. Epics already labelled
 * `solve:epic:ready` in the repo will be picked up by carrier too: clear that label first.
 * Evidence (counts before and after, ids) goes to the console and to <root>/e2e-evidence.log.
 */
const env = readEnv();
if (!env) console.warn('Carrier end-to-end test skipped: set CARRIER_E2E_REPO, CARRIER_E2E_AUTHOR_AGENT and CARRIER_E2E_REVIEWER_AGENT to run it (see the comment at the top of src/e2e/carrier.integration.test.ts).');

const minutes = (n: number) => n * 60_000;
const run = `${Date.now().toString(36).slice(-4)}`;

const readySlices = (name: string, fn: string, body: string, expected: string): EpicSpec => ({
  title: `${name} ${run}`,
  problem: `The sandbox has no \`${fn}\` yet and the README should list what exists.`,
  solution: `Add \`${fn}\` in \`${fn}.js\` (${body}), with its test in \`${fn}.test.js\`, and list it in the README under \`## Functions\`.`,
  slices: [
    {
      title: `Add ${fn}()`,
      body: `## Goal\nAdd \`${fn}\` in its own module.\n\n## Context\nSame shape as \`greet.js\` and \`greet.test.js\`.\n\n## Definition of done\n- [ ] \`${fn}\` is exported from \`${fn}.js\` and ${expected}\n- [ ] \`pnpm test\` passes\n- [ ] \`${fn}.test.js\` covers it through \`node --test\``,
    },
    {
      title: `List ${fn} in the README`,
      body: `## Goal\nList \`${fn}\` in the README.\n\n## Context\nThe README keeps one line per function under \`## Functions\`.\n\n## Definition of done\n- [ ] the README lists \`${fn}\` under \`## Functions\` (one line, same shape as the \`greet\` one)\n- [ ] \`pnpm test\` passes`,
    },
  ],
});

describe.skipIf(!env)('carrier end to end (real Claude, Codex, Forge and Solve)', () => {
  const e = env!;
  const root = env ? makeRoot() : '';
  const seed = env ? mkdtempSync(join(tmpdir(), 'carrier-e2e-seed-')) : '';
  const evidence = new Evidence(root);
  const sandbox = new Sandbox(e.repo, join(seed, 'sandbox'));
  const configFile = join(root, 'carrier.config.json');
  const logFile = join(root, 'carrier.stdout.log');
  const carriers: CarrierProcess[] = [];

  const startCarrier = () => {
    const carrier = new CarrierProcess(configFile, logFile).start();
    carriers.push(carrier);
    evidence.log(`carrier started pid=${carrier.pid}`);
    return carrier;
  };

  beforeAll(() => {
    evidence.log(`root=${root} repo=${e.repo} author=${e.authorAgent} ${e.author.provider}:${e.author.model} reviewer=${e.reviewerAgent} ${e.reviewer.provider}:${e.reviewer.model}`);
    const ready = sandbox.api<{ number: number }[]>(`repos/${e.repo}/issues?labels=solve:epic:ready&state=open&per_page=100`);
    if (ready.length > 0) throw new Error(`the repo already has epics marked ready (${ready.map((i) => `#${i.number}`).join(', ')}): carrier would import them`);
    sandbox.clone();
    sandbox.prepare(root, e.skillsDir);
    writeConfig({ root, repo: e.repo, authorAgent: e.authorAgent, reviewerAgent: e.reviewerAgent, author: e.author, reviewer: e.reviewer }, configFile);
  }, minutes(5));

  afterAll(async () => {
    for (const carrier of carriers) carrier.signal('SIGKILL');
    killMarked();
    rmSync(seed, { recursive: true, force: true });
    // The root stays when CARRIER_E2E_KEEP is set, for inspection; its evidence log is the record of the run.
    if (!process.env.CARRIER_E2E_KEEP) rmSync(root, { recursive: true, force: true });
  });

  /** Waits until the epic ends and returns its final row. */
  const untilEnded = (issue: number, timeout: number) =>
    waitFor(`epic #${issue} to leave running`, () => {
      const row = dbEpic(root, issue);
      return row && row.status !== 'queued' && row.status !== 'running' ? row : undefined;
    }, timeout, 5000);

  test.runIf(e.scenarios.includes('a'))(
    'a: an epic with two slices, marked ready by hand, ends ready-for-test with a real integration PR (author and reviewer are different profiles)',
    async () => {
      const epic = sandbox.seedEpic(readySlices('Reverse', 'reverse', 'reverses the characters of a string', 'returns `olleh` for `hello`'));
      const before = sandbox.count(epic.epic, epic.feature);
      evidence.log(`a: seeded epic #${epic.epic} slices ${epic.slices.map((n) => `#${n}`).join(',')} feature=${epic.feature}; GitHub before: ${JSON.stringify(before)}`);
      expect(e.authorAgent).not.toBe(e.reviewerAgent);

      sandbox.markReady(epic.epic);
      const carrier = startCarrier();
      const row = await untilEnded(epic.epic, minutes(60));
      evidence.log(`a: ended ${JSON.stringify(row)}; carrier exit=${JSON.stringify(carrier.exit)}`);
      evidence.log(`a: executions ${JSON.stringify(dbExecutions(root, epic.epic).map((x) => ({ stage: x.stage, status: x.status, error: x.error })))}`);
      const after = sandbox.count(epic.epic, epic.feature);
      evidence.log(`a: GitHub after: ${JSON.stringify(after)}; labels ${JSON.stringify(sandbox.labels(epic.epic))}`);

      expect(row.status).toBe('ready_for_test');
      expect(sandbox.labels(epic.epic)).toEqual(['solve:epic', 'solve:epic:ready-for-test']);
      expect(after.integrationPrs).toHaveLength(1);
      expect(row.prNumber).toBe(after.integrationPrs[0]);
      expect(row.workspace).toContain(join(root, 'worktrees'));
      const executions = dbExecutions(root, epic.epic);
      expect(executions.some((x) => x.stage === 'ship' && x.status === 'finished')).toBe(true);
      expect(executions.some((x) => x.stage === 'review' && x.status === 'finished')).toBe(true);
      expect(markedProcesses()).toEqual([]);
      carrier.signal('SIGINT');
      await carrier.stopped(minutes(1));
    },
    minutes(75),
  );
});
