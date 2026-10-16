import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  dialect: 'sqlite',
  schema: ['./src/storage/schema.ts', './src/storage/caller-results.ts', './src/storage/executions.ts', './src/storage/events.ts'],
  out: './src/storage/migrations',
});
