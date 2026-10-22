import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  dialect: 'sqlite',
  schema: ['./src/storage/schema.ts', './src/storage/caller-results.ts', './src/storage/executions.ts', './src/storage/events.ts', './src/storage/epic-slices.ts', './src/storage/epic-review-threads.ts'],
  out: './src/storage/migrations',
});
