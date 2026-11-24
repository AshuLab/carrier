import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, test } from 'vitest';
import { loadWithProviders } from '../config/testing.ts';
import { FakeSkills } from '../harnesses/fake-skills.ts';
import { runDoctor, type DoctorDeps } from './doctor.ts';

// The contract with the macOS app: its tests and the app run on fixtures read these files (macos/Tests/CarrierCoreTests/DoctorChecksTests.swift, `doctorFixtureOutput`).
// The checks are what `carrier doctor --json` prints for a setup with three repos: one in order, one whose reviewer cannot sign and whose Solve labels are missing, one the identity cannot read.
// UPDATE_FIXTURES=1 rewrites them.
const loaded = loadWithProviders({
  repos: [{ name: 'acme/web' }, { name: 'acme/api' }, { name: 'acme/a-really-long-repository-name-for-the-sidebar' }],
  profiles: { 'acme-author': { kind: 'forge', agent: 'acme-author' }, 'acme-reviewer': { kind: 'forge', agent: 'acme-reviewer' }, 'acme-lead': { kind: 'forge', agent: 'acme-lead' }, 'acme-gh': { kind: 'gh' } },
  orchestratorProfile: 'acme-gh',
  providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } },
  agents: {
    author: { profile: 'acme-author', provider: 'claude', model: 'm' },
    reviewer: { profile: 'acme-reviewer', provider: 'codex', model: 'm' },
    leadReviewer: { profile: 'acme-lead', provider: 'claude', model: 'm' },
  },
});
if (loaded.ok === false) throw new Error(JSON.stringify(loaded.errors));

const long = 'acme/a-really-long-repository-name-for-the-sidebar';
const deps: DoctorDeps = {
  which: () => true,
  mint: async (profile, repo) => {
    if (repo === 'acme/api' && profile.kind === 'forge' && profile.agent === 'acme-reviewer') throw new Error('acme-reviewer has no installations on acme/api');
    return 'token';
  },
  listLabels: async (_config, repo) => {
    if (repo === long) throw new Error('Not Found');
    return repo === 'acme/api' ? ['bug'] : ['solve:epic', 'solve:epic:ready'];
  },
  localModels: async () => [],
  loggedIn: async () => true,
  commandRuns: async () => true,
  startAgy: () => {
    throw new Error('no agy here');
  },
  skills: new FakeSkills(),
};

test('the doctor checks equal doctor.json, with a code and params beside each detail and each fix', async () => {
  // a folder too long for the control socket: the one warning, with a detail and a fix
  const checks = await runDoctor(loaded.config, `/Users/dev/${'carrier-'.repeat(9)}`, deps);
  const json = `${JSON.stringify(checks, null, 2)}\n`;
  for (const folder of ['Tests/Fixtures', 'DevFixtures']) {
    const file = fileURLToPath(new URL(`../../macos/${folder}/doctor.json`, import.meta.url));
    if (process.env.UPDATE_FIXTURES === '1') writeFileSync(file, json);
    expect(json).toBe(readFileSync(file, 'utf8'));
  }
  // every check that has words for a detail or a fix has its code, and the other way round
  for (const check of checks) {
    expect(check.detail !== undefined).toBe(check.detailCode !== undefined && check.detailParams !== undefined);
    expect(check.fix !== undefined).toBe(check.fixCode !== undefined && check.fixParams !== undefined);
  }
  expect(checks.map((check) => check.status)).toEqual(expect.arrayContaining(['ok', 'warn', 'fail']));
  expect(checks.some((check) => check.detail !== undefined && check.fix === undefined)).toBe(true);
});
