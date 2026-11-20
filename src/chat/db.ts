import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';

/** `chat.db`: the chat host's own file with its own migrations, so no other process migrates or writes the engine's database. */
export function openChatDatabase(file: string) {
  const db = drizzle(new Database(file));
  // persistent in the file, and before `migrate`: the pragma cannot run inside a transaction, and `migrate` opens one
  db.$client.pragma('journal_mode = WAL');
  migrate(db, { migrationsFolder: `${import.meta.dirname}/migrations` });
  return db;
}

export type ChatDb = ReturnType<typeof openChatDatabase>;
