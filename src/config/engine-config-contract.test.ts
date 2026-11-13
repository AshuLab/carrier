import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, test } from 'vitest';
import { defaults } from './load.ts';
import { configSchema } from './schema.ts';

// The contract with the macOS app: ContractTests.swift checks that EngineConfig.swift has these defaults and
// refuses what the engine refuses. UPDATE_FIXTURES=1 rewrites the file.
const cases: { field: string; value: unknown; valid: boolean }[] = [
  { field: 'pollIntervalMinutes', value: 0, valid: false },
  { field: 'pollIntervalMinutes', value: 0.5, valid: true },
  { field: 'logLevel', value: 'trace', valid: false },
  { field: 'logLevel', value: 'debug', valid: true },
  { field: 'finishedWindowDays', value: 0, valid: false },
  { field: 'finishedWindowDays', value: 30, valid: true },
  { field: 'finishedWindowDays', value: 31, valid: false },
  { field: 'limits.maxConcurrentEpics', value: 0, valid: false },
  { field: 'limits.maxConcurrentEpics', value: 1, valid: true },
  { field: 'limits.maxReviews', value: 0, valid: false },
  { field: 'limits.maxReviews', value: 1, valid: true },
  { field: 'limits.maxExecutionRetries', value: -1, valid: false },
  { field: 'limits.maxExecutionRetries', value: 0, valid: true },
  { field: 'limits.maxExecutionHours', value: 0, valid: false },
  { field: 'limits.maxExecutionHours', value: 'unlimited', valid: true },
  { field: 'limits.githubCallTimeoutSeconds', value: 0, valid: false },
  { field: 'limits.githubCallTimeoutSeconds', value: 1, valid: true },
];

test.each(cases)('the engine says $field = $value is valid: $valid', ({ field, value, valid }) => {
  const shape = configSchema.in.shape;
  const [first, second] = field.split('.') as [keyof typeof shape, (keyof typeof shape.limits.shape)?];
  const schema = second === undefined ? shape[first] : shape.limits.shape[second];
  expect(schema.safeParse(value).success).toBe(valid);
});

test('the defaults and the cases equal macos/Tests/Fixtures/engine-config.json', () => {
  const file = fileURLToPath(new URL('../../macos/Tests/Fixtures/engine-config.json', import.meta.url));
  const json = `${JSON.stringify({ defaults, cases }, null, 2)}\n`;
  if (process.env.UPDATE_FIXTURES === '1') writeFileSync(file, json);
  expect(json).toBe(readFileSync(file, 'utf8'));
});
