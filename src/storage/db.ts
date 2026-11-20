import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';

export function openDatabase(file: string) {
  const db = drizzle(new Database(file));
  // persistent in the file; it also lets the chat host's read-only usage reader never wait on, or be refused by, an engine commit.
  // Before `migrate`: the pragma cannot run inside a transaction, and `migrate` opens one
  db.$client.pragma('journal_mode = WAL');
  migrate(db, { migrationsFolder: `${import.meta.dirname}/migrations` });
  return db;
}

export type Db = ReturnType<typeof openDatabase>;
