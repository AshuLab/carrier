import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    exclude: ['src/**/*.integration.test.ts'],
    // Several tests start real processes (the engine holder, the CLI scripts); on a loaded CI runner that takes longer than vitest's 5 s.
    testTimeout: 30_000,
  },
});
