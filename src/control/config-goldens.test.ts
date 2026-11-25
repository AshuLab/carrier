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

function golden(name: string, built: EngineConfigRequest) {
  const folder = mkdtempSync(join(tmpdir(), 'cg-'));
  try {
    writeFileSync(engineConfigPathOf(folder), JSON.stringify(validEngineFile));
    expect(request.safeParse({ id: 1, ...built }).success).toBe(true);
    const json = `${JSON.stringify({ request: built, reply: { ok: true, data: withEngine(writeEngineConfig(built, engineConfigPathOf(folder), folder), () => {}) } }, null, 2)}\n`;
    const file = fileURLToPath(new URL(`../../macos/Tests/Fixtures/${name}.json`, import.meta.url));
    if (process.env.UPDATE_FIXTURES === '1') writeFileSync(file, json);
    expect(json).toBe(readFileSync(file, 'utf8'));
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
    changes: { pollIntervalMinutes: 2.5, logLevel: 'debug', finishedWindowDays: 15, limits: { maxConcurrentEpics: 3, maxReviews: 8, maxExecutionRetries: 3, maxExecutionHours: 'unlimited', githubCallTimeoutSeconds: 30 } },
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
