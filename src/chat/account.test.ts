import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { chatAgentsOf } from './account.ts';

let folder: string;
beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), 'acc-'));
  vi.stubEnv('CARRIER_HOME', folder);
});
afterEach(() => {
  rmSync(folder, { recursive: true, force: true });
  vi.unstubAllEnvs();
});

test('with no agents in chat.json the agents are the accounts of providers.json but Antigravity\'s, and the file is read each time', () => {
  expect(chatAgentsOf(undefined).map((agent) => agent.name)).toEqual(['claude', 'codex']);
  writeFileSync(join(folder, 'providers.json'), JSON.stringify({ providers: { claude: { harness: 'claude' }, teams: { harness: 'claude', configDir: '/logins/teams' }, agy: { harness: 'agy' } } }));
  expect(chatAgentsOf(undefined)).toEqual([{ name: 'claude', account: 'claude' }, { name: 'teams', account: 'teams' }]);
});

test('agents that chat.json lists are the only ones', () => {
  writeFileSync(join(folder, 'providers.json'), JSON.stringify({ providers: { claude: { harness: 'claude' }, teams: { harness: 'claude' } } }));
  expect(chatAgentsOf([{ name: 'mine', account: 'teams' }])).toEqual([{ name: 'mine', account: 'teams' }]);
});
