import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { engineConfigPathOf } from '../config/places.ts';
import { validEngineFile } from '../config/testing.ts';
import { withEngine, writeEngineConfig, type EngineConfigRequest } from './config.ts';
import { request } from './server.ts';

// The contract with the macOS app for the `config` requests of the engine: each file holds the request as the app builds it (its tests encode theirs and compare)
// and the reply the engine gives it. UPDATE_FIXTURES=1 rewrites them; the request must be one this server accepts.
// the bots a role may sign as: the engine reads the Agent Forge registry itself
let registry: string;
beforeEach(() => {
  registry = mkdtempSync(join(tmpdir(), 'cg-'));
  writeFileSync(join(registry, 'agents.json'), JSON.stringify({ agents: [{ name: 'artanis-agent' }, { name: 'nova' }] }));
  vi.stubEnv('AGENT_FORGE_CONFIG', join(registry, 'agents.json'));
});
afterEach(() => {
  vi.unstubAllEnvs();
  rmSync(registry, { recursive: true, force: true });
});

function golden(name: string, built: EngineConfigRequest, file: object = validEngineFile) {
  const folder = mkdtempSync(join(tmpdir(), 'cg-'));
  try {
    writeFileSync(engineConfigPathOf(folder), JSON.stringify(file));
    expect(request.safeParse({ id: 1, ...built }).success).toBe(true);
    const json = `${JSON.stringify({ request: built, reply: { ok: true, data: withEngine(writeEngineConfig(built, engineConfigPathOf(folder), folder), () => {}) } }, null, 2)}\n`;
    const golden = fileURLToPath(new URL(`../../macos/Tests/Fixtures/${name}.json`, import.meta.url));
    if (process.env.UPDATE_FIXTURES === '1') writeFileSync(golden, json);
    expect(json).toBe(readFileSync(golden, 'utf8'));
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
}

test('the setWatchedRepos request and reply equal engine-set-watched-repos.json', () => {
  golden('engine-set-watched-repos', { cmd: 'setWatchedRepos', repos: ['acme/web', 'AshuLab/carrier', 'new/one'] });
});

test('the editBehavior request and reply equal engine-edit-behavior.json', () => {
  golden('engine-edit-behavior', {
    cmd: 'editBehavior',
    changes: { pollIntervalMinutes: 2.5, logLevel: 'debug', finishedWindowDays: 15, limits: { maxConcurrentEpics: 3, maxReviews: 8, maxLeadRounds: 4, maxExecutionRetries: 3, maxExecutionHours: 'unlimited', githubCallTimeoutSeconds: 30 } },
  });
});

test('the editRole request and reply equal engine-edit-role.json', () => {
  golden('engine-edit-role', { cmd: 'editRole', role: 'reviewer', changes: { identity: { kind: 'forge', agent: 'nova' }, provider: 'codex', model: 'gpt-5', effort: null } });
});

test('the editRepoRole request and reply equal engine-edit-repo-role.json', () => {
  golden('engine-edit-repo-role', { cmd: 'editRepoRole', repo: 'acme/web', role: 'reviewer', fields: { profile: 'author-bot', model: 'qwen3-coder', effort: 'high', persona: { name: 'Rex' } } });
});

test('the editPersona request and reply equal engine-edit-persona.json', () => {
  golden('engine-edit-persona', { cmd: 'editPersona', role: 'author', name: 'Ada', prompt: null });
});

test('the editFailover request and reply equal engine-edit-failover.json', () => {
  golden('engine-edit-failover', { cmd: 'editFailover', role: 'author', first: { provider: 'codex', model: 'gpt-5', effort: 'high' }, second: { provider: 'agy' } });
});

test('the setLeadReviewer requests, on and off, and their replies equal engine-set-lead-reviewer.json and engine-set-lead-reviewer-off.json', () => {
  golden('engine-set-lead-reviewer', { cmd: 'setLeadReviewer', draft: { identity: { kind: 'gh' }, provider: 'claude', model: 'opus', effort: 'max' } });
  golden('engine-set-lead-reviewer-off', { cmd: 'setLeadReviewer', draft: null });
});

test('the setOrchestratorProfile request and reply equal engine-set-orchestrator-profile.json', () => {
  golden('engine-set-orchestrator-profile', { cmd: 'setOrchestratorProfile', name: 'author-bot' });
});

test('the addExtraReviewer request and reply equal engine-add-extra-reviewer.json', () => {
  golden('engine-add-extra-reviewer', { cmd: 'addExtraReviewer', draft: { name: 'Seguridad API', type: 'security', identity: { kind: 'forge', agent: 'nova' }, provider: 'claude', model: 'sonnet', effort: 'high' } });
});

// The file the requests that point at an extra reviewer start from: two of them, the first with its persona and its own failover steps.
const withExtraReviewers = {
  ...validEngineFile,
  agents: {
    ...validEngineFile.agents,
    extraReviewers: {
      'seguridad-api': { type: 'security', name: 'Seguridad API', profile: 'author-bot', provider: 'claude', model: 'sonnet', effort: 'high', persona: { name: 'Sentinel', prompt: 'Busca fallas de seguridad.' }, failover: [{ provider: 'codex', model: 'gpt-5' }] },
      usabilidad: { type: 'ux', name: 'Usabilidad', profile: 'reviewer-bot', provider: 'claude', model: 'opus' },
    },
  },
};

test('the removeExtraReviewer request and reply equal engine-remove-extra-reviewer.json', () => {
  golden('engine-remove-extra-reviewer', { cmd: 'removeExtraReviewer', key: 'seguridad-api' }, withExtraReviewers);
});

test('the editRole request that points at an extra reviewer and its reply equal engine-edit-extra-reviewer-role.json', () => {
  golden(
    'engine-edit-extra-reviewer-role',
    { cmd: 'editRole', role: { extraReviewer: 'seguridad-api' }, changes: { name: 'Seguridad del front', type: 'frontend-security', identity: { kind: 'forge', agent: 'nova' }, provider: 'codex', model: 'gpt-5-codex', effort: null } },
    withExtraReviewers,
  );
});

test('the editPersona request that points at an extra reviewer and its reply equal engine-edit-extra-reviewer-persona.json', () => {
  golden('engine-edit-extra-reviewer-persona', { cmd: 'editPersona', role: { extraReviewer: 'seguridad-api' }, name: 'Centinela', prompt: null }, withExtraReviewers);
});

test('the editFailover request that points at an extra reviewer and its reply equal engine-edit-extra-reviewer-failover.json', () => {
  golden('engine-edit-extra-reviewer-failover', { cmd: 'editFailover', role: { extraReviewer: 'seguridad-api' }, first: { provider: 'agy', model: 'gemini', effort: 'low' }, second: null }, withExtraReviewers);
});

test('the setRepoExtraReviewers requests, its own list, none and the key taken out, and their replies equal engine-set-repo-extra-reviewers.json, -none.json and -global.json', () => {
  const sec = { type: 'security', name: 'Seguridad API', profile: 'author-bot', provider: 'claude', model: 'sonnet', effort: 'high' };
  golden('engine-set-repo-extra-reviewers', { cmd: 'setRepoExtraReviewers', repo: 'acme/web', reviewers: { 'seguridad-api': sec, usabilidad: { type: 'ux', name: 'Usabilidad', profile: 'reviewer-bot', provider: 'codex', model: 'gpt-5' } } });
  golden('engine-set-repo-extra-reviewers-none', { cmd: 'setRepoExtraReviewers', repo: 'acme/web', reviewers: {} });
  golden('engine-set-repo-extra-reviewers-global', { cmd: 'setRepoExtraReviewers', repo: 'acme/web', reviewers: null }, {
    ...validEngineFile,
    repos: [validEngineFile.repos[0], { name: 'acme/web', agents: { author: { model: 'opus' }, extraReviewers: { 'seguridad-api': sec } } }],
  });
});
