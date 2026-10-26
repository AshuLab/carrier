import { execFileSync } from 'node:child_process';
import { describe, expect, test } from 'vitest';
import { childEnv } from './common.ts';

// Real Forge, real GitHub: a token revoked in the middle of an execution (the stand-in for the hour passing, the way
// docs/research/agent-forge.md does it) stops neither a `git push` through the credential helper nor `agent-forge gh`.
// It only runs when all three variables are set explicitly:
//   CARRIER_IT_REPO=owner/name             a throwaway test repo the bot can push to (contents: write)
//   CARRIER_IT_FORGE_AGENT=<agent>         a bot in the Forge registry, installed on that repo
//   CARRIER_IT_CWD=<a clone of that repo>  its origin is under the same owner (Forge picks the installation from it); its HEAD is what gets pushed
// It pushes one throwaway branch and deletes it at the end. No token or key is printed.
const { CARRIER_IT_REPO: repo, CARRIER_IT_FORGE_AGENT: agent, CARRIER_IT_CWD: cwd } = process.env;
const enabled = Boolean(repo && agent && cwd);
if (!enabled) console.warn('Forge token renewal integration test skipped: set CARRIER_IT_REPO, CARRIER_IT_FORGE_AGENT and CARRIER_IT_CWD to run it.');

const run = (command: string, args: string[], env: NodeJS.ProcessEnv = process.env, input?: string) =>
  execFileSync(command, args, { cwd, env, input, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();

describe.skipIf(!enabled)('a token revoked mid-run against a real Forge bot', () => {
  test(
    'git push through the helper and agent-forge gh still work',
    async () => {
      // The token the run "started with", then revoked: GitHub answers 401 the same for an expired and a revoked token.
      const started = run('agent-forge', ['token', '--agent', agent!]);
      const asStarted = (method: string, path: string) =>
        fetch(`https://api.github.com${path}`, { method, headers: { authorization: `Bearer ${started}`, 'user-agent': 'carrier-it' } });
      expect((await asStarted('DELETE', '/installation/token')).status).toBe(204);
      expect((await asStarted('GET', '/installation/repositories')).status).toBe(401);

      // What the harness gives the child: the revoked token in GH_TOKEN, plus the helper and the agent's name.
      const env = childEnv({ binary: 'claude', githubToken: started, forgeAgent: agent, baseEnv: { ...process.env, GIT_TERMINAL_PROMPT: '0' } });

      // One helper answer: it signs a JWT and makes two requests to GitHub. Printed, not asserted.
      const timer = performance.now();
      run('git', ['credential', 'fill'], env, 'protocol=https\nhost=github.com\n\n');
      console.log(`one helper answer took ${Math.round(performance.now() - timer)} ms`);

      const branch = `carrier-it-token-renewal-${Date.now()}`;
      try {
        run('git', ['push', `https://github.com/${repo}.git`, `HEAD:refs/heads/${branch}`], env);
        expect(run('agent-forge', ['gh', agent!, 'api', `repos/${repo}/branches/${branch}`, '--jq', '.name'], env)).toBe(branch);
      } finally {
        try {
          run('agent-forge', ['gh', agent!, 'api', '-X', 'DELETE', `repos/${repo}/git/refs/heads/${branch}`], env);
        } catch (error) {
          console.warn(`could not delete the throwaway branch ${branch} of ${repo}: ${error instanceof Error ? error.message.split('\n')[0] : 'unknown error'}`);
        }
      }
    },
    120_000,
  );
});
