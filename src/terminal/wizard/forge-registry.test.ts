import { join } from 'node:path';
import { writeFileSync } from 'node:fs';
import { expect, test } from 'vitest';
import { readForgeAgents } from './forge-registry.ts';
import { useTempDir } from './testing.ts';

const dir = useTempDir();

test('the Forge registry yields names and labels, and nothing when there is none', () => {
  const file = join(dir, 'agents.json');
  writeFileSync(file, JSON.stringify({ agents: [{ name: 'a', label: 'A', privateKeyPath: '/secret' }, { name: 'b' }, { nope: 1 }] }));
  expect(readForgeAgents(file)).toEqual([{ name: 'a', label: 'A' }, { name: 'b' }]);
  expect(readForgeAgents(join(dir, 'missing.json'))).toEqual([]);
  writeFileSync(file, '{');
  expect(() => readForgeAgents(file)).toThrow();
});
