import { expect, test } from 'vitest';
import type { AgentTask } from '../execution/agent-runner.ts';
import type { GitHubProfile } from '../integrations/github.ts';
import { buildClaudeCommand } from './claude.ts';
import { botIdFromGitHub, profileCredentials } from './credentials.ts';
import { HostAgentRunner } from './host-runner.ts';

const task = (profile: string, repo = 'AshuLab/carrier'): AgentTask => ({
  executionId: `exec-${profile}`, repo, epic: 3, stage: 'ship', profile, harness: 'claude', model: 'm',
  workspace: '/work', resultPath: '/root/orchestrator/results/x.json', timeoutMs: null, context: { previousSummaries: [] },
});
const profiles: Record<string, GitHubProfile> = {
  author: { kind: 'forge', agent: 'artanis-agent' },
  reviewer: { kind: 'forge', agent: 'tassadar-agent' },
  diego: { kind: 'gh' },
};
const ids: Record<string, number> = { 'artanis-agent': 325794106, 'tassadar-agent': 42 };

test('a Forge profile gets its own token and the bot commit identity with the numeric bot id', async () => {
  const minted: string[] = [];
  const credentials = profileCredentials({
    profiles,
    mint: async (profile, repo) => (minted.push(`${profile.kind === 'forge' ? profile.agent : 'gh'}@${repo}`), `ghs_${profile.kind === 'forge' ? profile.agent : 'gh'}_${minted.length}`),
    botId: async (agent) => ids[agent]!,
  });
  const [a, b] = await Promise.all([credentials(task('author')), credentials(task('reviewer', 'AshuLab/other'))]);

  expect(a).toEqual({
    githubToken: 'ghs_artanis-agent_1',
    forgeAgent: 'artanis-agent',
    gitIdentity: { name: 'artanis-agent[bot]', email: '325794106+artanis-agent[bot]@users.noreply.github.com' },
  });
  expect(b).toEqual({
    githubToken: 'ghs_tassadar-agent_2',
    forgeAgent: 'tassadar-agent',
    gitIdentity: { name: 'tassadar-agent[bot]', email: '42+tassadar-agent[bot]@users.noreply.github.com' },
  });
  expect(minted).toEqual(['artanis-agent@AshuLab/carrier', 'tassadar-agent@AshuLab/other']);
});

test('a gh profile keeps the user\'s own login: its token, no identity override, no bot lookup', async () => {
  const credentials = profileCredentials({
    profiles,
    mint: async (profile) => (profile.kind === 'gh' ? 'gho_mine' : 'unexpected'),
    botId: async () => Promise.reject(new Error('must not be asked')),
  });
  expect(await credentials(task('diego'))).toEqual({ githubToken: 'gho_mine' }); // and no forgeAgent
});

test('the token goes to the child environment and to nothing else of the command', async () => {
  const credentials = profileCredentials({ profiles, mint: async () => 'ghs_SECRET', botId: async () => 7 });
  const command = buildClaudeCommand(task('author'), { binary: '/real/claude', baseEnv: { PATH: '/bin' }, ...(await credentials(task('author'))) });
  expect(command.env).toMatchObject({
    GH_TOKEN: 'ghs_SECRET', GITHUB_TOKEN: 'ghs_SECRET',
    GIT_AUTHOR_NAME: 'artanis-agent[bot]', GIT_AUTHOR_EMAIL: '7+artanis-agent[bot]@users.noreply.github.com',
    GIT_COMMITTER_NAME: 'artanis-agent[bot]', GIT_COMMITTER_EMAIL: '7+artanis-agent[bot]@users.noreply.github.com',
  });
  expect([command.bin, command.cwd, ...command.args].join('\n')).not.toContain('ghs_SECRET');
});

test('a Forge failure, an unknown profile or a bot lookup that fails is auth_failed for the runner, without starting the agent', async () => {
  const failing = (mint: () => Promise<string>, botId = async () => 1) => new HostAgentRunner({ binaries: { claude: '/does/not/exist' }, credentials: profileCredentials({ profiles, mint, botId }) });
  for (const [runner, profile] of [
    [failing(async () => Promise.reject(new Error('could not mint a token for artanis-agent: Agent not found: artanis-agent'))), 'author'],
    [failing(async () => 'ghs_x'), 'ghost'],
    [failing(async () => 'ghs_x', async () => Promise.reject(new Error('HTTP 502'))), 'author'],
  ] as const) {
    const run = runner.run(task(profile));
    const output: string[] = [];
    run.onOutput((_stream, chunk) => output.push(chunk));
    expect((await run.done).exit).toBe('auth_failed');
    expect(output.join('')).toContain(`no GitHub token for profile "${profile}"`);
  }
});

test('botIdFromGitHub asks the public users endpoint with the token, once per agent, and rejects what is not an id', async () => {
  const calls: { url: string; auth: string | undefined }[] = [];
  const respond = (body: unknown, status = 200) => async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), auth: (init?.headers as Record<string, string>).authorization });
    return new Response(JSON.stringify(body), { status });
  };
  const botId = botIdFromGitHub(respond({ id: 325794106, login: 'artanis-agent[bot]' }) as typeof fetch);
  expect(await botId('artanis-agent', 'ghs_t')).toBe(325794106);
  expect(await botId('artanis-agent', 'ghs_other')).toBe(325794106);
  expect(calls).toEqual([{ url: 'https://api.github.com/users/artanis-agent%5Bbot%5D', auth: 'Bearer ghs_t' }]);

  await expect(botIdFromGitHub(respond({ message: 'Not Found' }, 404) as typeof fetch)('x', 't')).rejects.toThrow('HTTP 404');
  await expect(botIdFromGitHub(respond({ id: 'abc' }) as typeof fetch)('x', 't')).rejects.toThrow();
});
