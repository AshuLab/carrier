import { createScopedLogger } from '@ashulab/universal-logger';
import { expect, test } from 'vitest';

test('universal-logger exposes createScopedLogger', () => {
  expect(typeof createScopedLogger).toBe('function');
});
