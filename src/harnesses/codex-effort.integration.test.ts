import { spawnSync } from 'node:child_process';
import { mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';

// The real Codex, through the user's own `codex` binary and login, in a temporary folder: `-c model_reasoning_effort=<level>`,
// the pair Carrier passes for a role's effort, is honoured by `exec` and by `exec resume`, which print the effort they run with.
// It sends three tiny prompts, so it uses a little of the user's own plan. It only runs when this is set explicitly:
//   CARRIER_IT_CODEX=1   (optional: CARRIER_IT_CODEX_COMMAND=<path to the codex binary>, else the one on the path)
// The sandbox is read-only here (as a config key, which `resume` also takes): nothing in these prompts needs more. No token is read or printed.
const enabled = process.env.CARRIER_IT_CODEX === '1';
const bin = process.env.CARRIER_IT_CODEX_COMMAND ?? 'codex';

describe.skipIf(!enabled)('a role effort against the real Codex', () => {
  let folder: string;
  beforeAll(() => {
    folder = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-codex-effort-')));
  });
  afterAll(() => rmSync(folder, { recursive: true, force: true }));

  const codex = (args: string[]) => {
    const run = spawnSync(bin, [...args, '--skip-git-repo-check', '-c', 'sandbox_mode="read-only"'], { cwd: folder, encoding: 'utf8', input: '', timeout: 150_000 });
    return `${run.stdout}\n${run.stderr}`;
  };

  test('exec and exec resume run with the effort they are given', { timeout: 450_000 }, () => {
    const first = codex(['exec', 'Reply with just: OK', '-c', 'model_reasoning_effort=low']);
    expect(first).toMatch(/reasoning effort: low/);
    const session = /session id: (\S+)/.exec(first)?.[1];
    expect(session).toBeTruthy();
    // `resume` takes the effort given now, not the one the session began with.
    expect(codex(['exec', 'resume', session!, 'Reply with just: OK', '-c', 'model_reasoning_effort=high'])).toMatch(/reasoning effort: high/);
  });
});
