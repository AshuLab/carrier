import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, afterEach, beforeAll, describe, expect, test } from 'vitest';
import {
  CarrierProcess,
  Evidence,
  Sandbox,
  dbEpic,
  claudeSessionFile,
  dbEvents,
  dbExecutions,
  dbResultCount,
  killStragglers,
  killMarked,
  makeRoot,
  markedProcesses,
  readEnv,
  resultFile,
  sleep,
  stragglers,
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
 *   CARRIER_E2E_REVIEWER=codex:gpt-5.6-luna          idem
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

const epicSpec = (name: string, fn: string, body: string, expected: string, twoSlices = true): EpicSpec => ({
  title: `${name} ${run}`,
  problem: `The sandbox has no \`${fn}\` yet and the README should list what exists.`,
  solution: `Add \`${fn}\` in \`${fn}.js\` (${body}), with its test in \`${fn}.test.js\`, and list it in the README under \`## Functions\`.`,
  slices: twoSlices ? [
    {
      title: `Add ${fn}()`,
      body: `## Goal\nAdd \`${fn}\` in its own module.\n\n## Context\nSame shape as \`greet.js\` and \`greet.test.js\`.\n\n## Definition of done\n- [ ] \`${fn}\` is exported from \`${fn}.js\` and ${expected}\n- [ ] \`pnpm test\` passes\n- [ ] \`${fn}.test.js\` covers it through \`node --test\``,
    },
    {
      title: `List ${fn} in the README`,
      body: `## Goal\nList \`${fn}\` in the README.\n\n## Context\nThe README keeps one line per function under \`## Functions\`.\n\n## Definition of done\n- [ ] the README lists \`${fn}\` under \`## Functions\` (one line, same shape as the \`greet\` one)\n- [ ] \`pnpm test\` passes`,
    },
  ] : [
    {
      title: `Add ${fn}() and list it`,
      body: `## Goal\nAdd \`${fn}\` in its own module and list it in the README.\n\n## Context\nSame shape as \`greet.js\` and \`greet.test.js\`; the README keeps one line per function under \`## Functions\`.\n\n## Definition of done\n- [ ] \`${fn}\` is exported from \`${fn}.js\` and ${expected}\n- [ ] \`${fn}.test.js\` covers it through \`node --test\`\n- [ ] the README lists \`${fn}\` under \`## Functions\`\n- [ ] \`pnpm test\` passes`,
    },
  ],
});

describe.skipIf(!env)('carrier end to end (real Claude, Codex, Forge and Solve)', () => {
  // The body of a skipped describe still runs to collect its tests: without the variables it must not touch them.
  const e = env ?? { repo: '', authorAgent: '', reviewerAgent: '', author: { provider: 'claude' as const, model: '' }, reviewer: { provider: 'codex' as const, model: '' }, scenarios: [] };
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

  // A scenario that fails halfway must not leave its carrier holding the instance lock for the next one.
  afterEach(() => {
    for (const carrier of carriers.splice(0)) carrier.signal('SIGKILL');
    killMarked();
    killStragglers(root);
  });

  afterAll(async () => {
    for (const carrier of carriers) carrier.signal('SIGKILL');
    killMarked();
    rmSync(seed, { recursive: true, force: true });
    // The root stays when CARRIER_E2E_KEEP is set, for inspection; its evidence log is the record of the run.
    if (!process.env.CARRIER_E2E_KEEP) rmSync(root, { recursive: true, force: true });
  });

  /** Fails fast when the epic has already left running (a person is needed): waiting on for its agent's JSON would only hang. */
  const stillRunning = (issue: number) => {
    const row = dbEpic(root, issue);
    if (row && row.status !== 'queued' && row.status !== 'running') throw new Error(`epic #${issue} ended as ${row.status} (${row.needsHumanReason ?? row.lastError ?? 'no reason'})`);
  };

  /** Waits until the epic ends and returns its final row. */
  const untilEnded = (issue: number, timeout: number) =>
    waitFor(`epic #${issue} to leave running`, () => {
      const row = dbEpic(root, issue);
      return row && row.status !== 'queued' && row.status !== 'running' ? row : undefined;
    }, timeout, 5000);

  test.runIf(e.scenarios.includes('a'))(
    'a: an epic with two slices, marked ready by hand, ends ready-for-test with a real integration PR (author and reviewer are different profiles)',
    async () => {
      const epic = sandbox.seedEpic(epicSpec('Reverse', 'reverse', 'reverses the characters of a string', 'returns `olleh` for `hello`'));
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

  // Nothing may be created twice: PR heads, epic comments and commit messages are each unique.
  const expectNoDuplicates = (after: ReturnType<Sandbox['count']>) => {
    expect(new Set(after.prHeads).size).toBe(after.prHeads.length);
    expect(new Set(after.epicCommentBodies).size).toBe(after.epicCommentBodies.length);
    expect(new Set(after.commitMessages).size).toBe(after.commitMessages.length);
  };

  const stop = async (carrier: CarrierProcess) => {
    carrier.signal('SIGINT');
    await carrier.stopped(minutes(2));
  };

  test.runIf(e.scenarios.includes('b'))(
    'b: concurrency 2, two epics of the same repo end with separate workspaces and without interference',
    async () => {
      const x = sandbox.seedEpic(epicSpec('Double', 'double', 'returns twice a number', 'returns `8` for `4`', false));
      const y = sandbox.seedEpic(epicSpec('Negate', 'negate', 'returns the opposite of a number', 'returns `-3` for `3`', false));
      evidence.log(`b: seeded #${x.epic} (${x.feature}) and #${y.epic} (${y.feature})`);
      sandbox.markReady(x.epic);
      sandbox.markReady(y.epic);
      const carrier = startCarrier();
      const live = await waitFor('an agent of each epic running at once', () => {
        const running = [x, y].map((a) => dbExecutions(root, a.epic).filter((r) => r.status === 'running').length);
        return running.every((n) => n === 1) && running;
      }, minutes(5), 1000);
      evidence.log(`b: both epics running at once; running executions per epic ${live.join(' and ')}; agent processes ${JSON.stringify(markedProcesses().map((p) => p.pid))}`);
      expect(markedProcesses()).toHaveLength(2);
      const [rx, ry] = await Promise.all([untilEnded(x.epic, minutes(60)), untilEnded(y.epic, minutes(60))]);
      const ax = sandbox.count(x.epic, x.feature);
      const ay = sandbox.count(y.epic, y.feature);
      evidence.log(`b: #${x.epic} ${JSON.stringify(rx)}`);
      evidence.log(`b: #${y.epic} ${JSON.stringify(ry)}`);
      evidence.log(`b: GitHub #${x.epic}: ${JSON.stringify(ax)}`);
      evidence.log(`b: GitHub #${y.epic}: ${JSON.stringify(ay)}`);

      expect([rx.status, ry.status]).toEqual(['ready_for_test', 'ready_for_test']);
      expect(rx.workspace).not.toBe(ry.workspace);
      expect(rx.workspace).toContain(join(root, 'worktrees'));
      expect(ry.workspace).toContain(join(root, 'worktrees'));
      for (const [row, a] of [[rx, x], [ry, y]] as const) {
        expect(row.workspace).toContain(a.feature);
        expect(existsSync(join(root, 'reviews', 'carrier-sandbox', String(a.epic)))).toBe(true);
      }
      // No interference: each integration PR touches only its own function, and each epic has its own PRs and comments.
      const fx = sandbox.prFiles(ax.integrationPrs[0]!);
      const fy = sandbox.prFiles(ay.integrationPrs[0]!);
      evidence.log(`b: files of the integration PRs: #${ax.integrationPrs[0]} ${JSON.stringify(fx)} #${ay.integrationPrs[0]} ${JSON.stringify(fy)}`);
      expect(fx.every((f) => ['double.js', 'double.test.js', 'README.md'].includes(f))).toBe(true);
      expect(fy.every((f) => ['negate.js', 'negate.test.js', 'README.md'].includes(f))).toBe(true);
      expect(fx).toContain('double.js');
      expect(fy).toContain('negate.js');
      expectNoDuplicates(ax);
      expectNoDuplicates(ay);
      expect(markedProcesses()).toEqual([]);
      await stop(carrier);
    },
    minutes(75),
  );

  test.runIf(e.scenarios.includes('c'))(
    'c: kill -9 of carrier in the middle of ship, the restart resumes the epic without duplicate PRs, comments or commits',
    async () => {
      const epic = sandbox.seedEpic(epicSpec('Initials', 'initials', 'returns the initials of a name', 'returns `JD` for `John Doe`'));
      sandbox.markReady(epic.epic);
      const first = startCarrier();
      // Mid-ship: work is already on GitHub (a slice PR) while the author still runs.
      await waitFor('a slice PR on GitHub while ship is still running', () => {
        const running = dbExecutions(root, epic.epic).some((r) => r.stage === 'ship' && r.status === 'running');
        return running && sandbox.count(epic.epic, epic.feature).prs >= 1;
      }, minutes(20), 5000);
      const before = sandbox.count(epic.epic, epic.feature);
      const killed = dbExecutions(root, epic.epic).find((r) => r.status === 'running')!;
      evidence.log(`c: GitHub before kill -9: ${JSON.stringify(before)}`);
      first.signal('SIGKILL');
      evidence.log(`c: kill -9 carrier pid=${first.pid}; exit=${JSON.stringify(await first.stopped(30_000))}`);
      const orphans = markedProcesses();
      evidence.log(`c: agent processes left running by the dead carrier: ${JSON.stringify(orphans)}`);
      expect(orphans.length).toBeGreaterThan(0);

      const second = startCarrier();
      const row = await untilEnded(epic.epic, minutes(60));
      const after = sandbox.count(epic.epic, epic.feature);
      const executions = dbExecutions(root, epic.epic);
      evidence.log(`c: ended ${JSON.stringify(row)}`);
      evidence.log(`c: executions ${JSON.stringify(executions.map((r) => ({ id: r.executionId.slice(0, 8), stage: r.stage, status: r.status, session: r.sessionId?.slice(0, 8), error: r.error })))}`);
      evidence.log(`c: GitHub after: ${JSON.stringify(after)}`);
      evidence.log(`c: orchestrator.log mentions of the orphan: ${readFileSync(join(root, 'orchestrator', 'logs', 'orchestrator.log'), 'utf8').split('\n').filter((l) => l.includes(killed.executionId)).length}`);

      expect(row.status).toBe('ready_for_test');
      expect(executions.find((r) => r.executionId === killed.executionId)!.status).toBe('interrupted');
      const resumed = executions.filter((r) => r.stage === 'ship').at(-1)!;
      expect(resumed.executionId).not.toBe(killed.executionId);
      expect(resumed.sessionId).toBe(killed.sessionId); // the same session, resumed
      expect(after.integrationPrs).toHaveLength(1);
      expect(after.prs).toBe(3); // two slice PRs and the integration PR, before and after the cut
      expect(after.prs).toBeGreaterThanOrEqual(before.prs);
      expect(after.commits).toBeGreaterThanOrEqual(before.commits);
      expectNoDuplicates(after);
      expect(markedProcesses()).toEqual([]);
      await stop(second);
    },
    minutes(90),
  );

  test.runIf(e.scenarios.includes('d'))(
    'd: kill -9 after the agent wrote its JSON and before the import: imported exactly once on restart; a truncated JSON is retried',
    async () => {
      const epic = sandbox.seedEpic(epicSpec('Clamp', 'clamp', 'limits a number to a range', 'returns `5` for `clamp(9, 0, 5)`', false));
      sandbox.markReady(epic.epic);
      const first = startCarrier();
      const exec = await waitFor('the ship execution to start', () => dbExecutions(root, epic.epic).find((r) => r.stage === 'ship'), minutes(5), 2000);
      // The agent writes the JSON a few seconds before its process ends: cut carrier in that window.
      const file = resultFile(root, exec.executionId);
      await waitFor('the ship JSON', () => (stillRunning(epic.epic), existsSync(file) && statSync(file).size > 0), minutes(30), 100);
      first.signal('SIGKILL');
      await first.stopped(30_000);
      const imported = dbResultCount(root, exec.executionId);
      evidence.log(`d: kill -9 with the JSON on disk (${statSync(file).size} bytes) and ${imported} imported results; ship execution status ${dbExecutions(root, epic.epic)[0]!.status}`);
      expect(imported).toBe(0);
      const json = readFileSync(file, 'utf8');
      const before = sandbox.count(epic.epic, epic.feature);
      evidence.log(`d: GitHub before restart: ${JSON.stringify(before)}`);

      const second = startCarrier();
      await waitFor('the result imported', () => dbResultCount(root, exec.executionId) === 1, minutes(3), 1000);
      const afterImport = dbExecutions(root, epic.epic);
      evidence.log(`d: imported ${dbResultCount(root, exec.executionId)} time(s); executions ${JSON.stringify(afterImport.map((r) => ({ stage: r.stage, status: r.status })))}`);
      expect(readFileSync(file, 'utf8')).toBe(json);
      expect(afterImport.filter((r) => r.stage === 'ship')).toHaveLength(1); // the stage was not launched again

      // Now, with carrier alive, cut the reviewer's JSON in half before its process ends: a technical failure, retried.
      const review = await waitFor('the review execution', () => dbExecutions(root, epic.epic).find((r) => r.stage === 'review'), minutes(5), 2000);
      const reviewFile = resultFile(root, review.executionId);
      await waitFor('the review JSON', () => (stillRunning(epic.epic), existsSync(reviewFile) && statSync(reviewFile).size > 0), minutes(30), 100);
      // The agent may read its file back and rewrite it, so keep cutting it until its process is gone: what carrier finds is a truncated file.
      let cuts = 0;
      while (dbExecutions(root, epic.epic).find((r) => r.executionId === review.executionId)?.status === 'running') {
        try {
          const text = readFileSync(reviewFile, 'utf8');
          JSON.parse(text);
          writeFileSync(reviewFile, text.slice(0, Math.floor(text.length / 2)));
          cuts++;
        } catch {
          // already truncated, or the agent deleted it to rewrite it: look again
        }
        await sleep(50);
      }
      evidence.log(`d: cut the review JSON ${cuts} time(s) while its agent ran; what carrier found: ${existsSync(reviewFile) ? readFileSync(reviewFile, 'utf8').length : 0} bytes`);

      const row = await untilEnded(epic.epic, minutes(60));
      const executions = dbExecutions(root, epic.epic);
      const events = dbEvents(root, epic.epic).map((v) => v.type);
      const after = sandbox.count(epic.epic, epic.feature);
      evidence.log(`d: ended ${JSON.stringify(row)}`);
      evidence.log(`d: executions ${JSON.stringify(executions.map((r) => ({ id: r.executionId.slice(0, 8), stage: r.stage, status: r.status, session: r.sessionId?.slice(0, 8), error: r.error })))}; events ${JSON.stringify(events)}`);
      evidence.log(`d: GitHub after: ${JSON.stringify(after)}`);

      expect(row.status).toBe('ready_for_test');
      expect(dbResultCount(root, exec.executionId)).toBe(1);
      // `review` was read when the execution started, before Codex reported its session: the id comes from the final row.
      const cut = executions.find((r) => r.executionId === review.executionId)!;
      expect(cut.status).toBe('invalid_result');
      expect(cut.error).toBe('result is not valid JSON');
      const retried = executions.filter((r) => r.stage === 'review').slice(1);
      expect(retried.length).toBeGreaterThanOrEqual(1);
      expect(cut.sessionId).not.toBeNull();
      expect(retried[0]!.sessionId).toBe(cut.sessionId); // resumed, not rebuilt
      expect(events).toContain('execution_retried');
      expect(row.round).toBe(1); // a technical failure does not spend a review round
      expect(after.integrationPrs).toHaveLength(1);
      expect(after.prs).toBe(2);
      expectNoDuplicates(after);
      await stop(second);
    },
    minutes(90),
  );

  test.runIf(e.scenarios.includes('e'))(
    'e: Ctrl+C in the middle of an execution, the restart resumes from the preserved session',
    async () => {
      const epic = sandbox.seedEpic(epicSpec('Square', 'square', 'multiplies a number by itself', 'returns `9` for `3`', false));
      sandbox.markReady(epic.epic);
      const first = startCarrier();
      const exec = await waitFor('the ship execution with its session saved', () => dbExecutions(root, epic.epic).find((r) => r.stage === 'ship' && r.sessionId), minutes(5), 2000);
      // Let the agent get a little way in, so there is something to resume.
      await waitFor('some work on the session', () => {
        const file = claudeSessionFile(exec.sessionId!);
        return file !== null && statSync(file).size > 20_000;
      }, minutes(5), 2000);
      const before = sandbox.count(epic.epic, epic.feature);
      const sessionFile = claudeSessionFile(exec.sessionId!)!;
      const sizeBefore = statSync(sessionFile).size;
      evidence.log(`e: Ctrl+C (SIGINT) to carrier pid=${first.pid}; session ${exec.sessionId} file ${sessionFile} ${sizeBefore} bytes; GitHub before: ${JSON.stringify(before)}`);
      first.signal('SIGINT');
      const exit = await first.stopped(minutes(1));
      const interrupted = dbExecutions(root, epic.epic);
      const epicRow = dbEpic(root, epic.epic)!;
      evidence.log(`e: carrier exit=${JSON.stringify(exit)}; epic ${epicRow.status}/${epicRow.stage}; executions ${JSON.stringify(interrupted.map((r) => ({ stage: r.stage, status: r.status })))}; agent processes left: ${JSON.stringify(markedProcesses())}; others under the root: ${JSON.stringify(stragglers(root))}`);
      expect(exit.code).toBe(0);
      expect(epicRow.status).toBe('running');
      expect(interrupted[0]!.status).toBe('interrupted');
      expect(markedProcesses()).toEqual([]);
      killStragglers(root);
      expect(existsSync(sessionFile)).toBe(true); // the session survived

      const second = startCarrier();
      const row = await untilEnded(epic.epic, minutes(60));
      const executions = dbExecutions(root, epic.epic);
      const after = sandbox.count(epic.epic, epic.feature);
      evidence.log(`e: ended ${JSON.stringify(row)}`);
      evidence.log(`e: executions ${JSON.stringify(executions.map((r) => ({ id: r.executionId.slice(0, 8), stage: r.stage, status: r.status, session: r.sessionId?.slice(0, 8) })))}; session file grew ${sizeBefore} -> ${statSync(sessionFile).size} bytes`);
      evidence.log(`e: GitHub after: ${JSON.stringify(after)}`);

      expect(row.status).toBe('ready_for_test');
      const resumed = executions.filter((r) => r.stage === 'ship')[1]!;
      expect(resumed.sessionId).toBe(exec.sessionId);
      expect(statSync(sessionFile).size).toBeGreaterThan(sizeBefore); // the resumed run appended to the same session
      expect(after.integrationPrs).toHaveLength(1);
      expect(after.prs).toBe(2);
      expectNoDuplicates(after);
      await stop(second);
    },
    minutes(90),
  );
});
