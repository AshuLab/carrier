import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  dialect: 'sqlite',
  schema: './src/chat/schema.ts',
  out: './src/chat/migrations',
});
