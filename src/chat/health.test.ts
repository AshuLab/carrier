import { expect, test } from 'vitest';
import { gitState, type HealthProbes } from './health.ts';

function probes(path: string, code = 0) {
  const ran: string[] = [];
  const fake: HealthProbes = { loggedIn: async () => true, exitCode: async (command, args) => (ran.push([command, ...args].join(' ')), code), gitPath: () => path };
  return { ran, fake };
}

test('the system git, the stub of a Mac without the Command Line Tools, is never run: xcode-select asks instead', async () => {
  const ready = probes('/usr/bin/git');
  expect(await gitState({ binaryFound: () => true, probes: ready.fake })).toBe('ready');
  expect(ready.ran).toEqual(['xcode-select -p']);
  expect(await gitState({ binaryFound: () => true, probes: probes('/usr/bin/git', 2).fake })).toBe('missing');
});

test('any other git runs --version', async () => {
  const other = probes('/opt/homebrew/bin/git');
  expect(await gitState({ binaryFound: () => true, probes: other.fake })).toBe('ready');
  expect(other.ran).toEqual(['/opt/homebrew/bin/git --version']);
  expect(await gitState({ binaryFound: () => true, probes: probes('/opt/homebrew/bin/git', 1).fake })).toBe('missing');
});

test('no git on the PATH is missing and nothing runs', async () => {
  const none = probes('/usr/bin/git');
  expect(await gitState({ binaryFound: () => false, probes: none.fake })).toBe('missing');
  expect(none.ran).toEqual([]);
});
