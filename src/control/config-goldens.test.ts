import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test } from 'vitest';
import { engineConfigPathOf } from '../config/places.ts';
import { validEngineFile } from '../config/testing.ts';
import { withEngine, writeEngineConfig, type EngineConfigRequest } from './config.ts';
import { request } from './server.ts';

// The contract with the macOS app for the `config` requests of the engine: each file holds the request as the app builds it (its tests encode theirs and compare)
// and the reply the engine gives it. UPDATE_FIXTURES=1 rewrites them; the request must be one this server accepts.
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
