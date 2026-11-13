import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, test } from 'vitest';
import { capabilities as chat } from '../chat/server.ts';
import { capabilities as engine } from './server.ts';

// The contract with the macOS app: ContractTests.swift checks that every name here is a case of
// ControlClient.Capability, since the app drops a name it does not know and the feature never shows. UPDATE_FIXTURES=1 rewrites it.
test('the hellos announce the capabilities in macos/Tests/Fixtures/capabilities.json', () => {
  const file = fileURLToPath(new URL('../../macos/Tests/Fixtures/capabilities.json', import.meta.url));
  const json = `${JSON.stringify({ engine, chat }, null, 2)}\n`;
  if (process.env.UPDATE_FIXTURES === '1') writeFileSync(file, json);
  expect(json).toBe(readFileSync(file, 'utf8'));
});
