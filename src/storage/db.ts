import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';

export function openDatabase(file: string) {
  const db = drizzle(new Database(file));
  migrate(db, { migrationsFolder: `${import.meta.dirname}/migrations` });
  return db;
}

export type Db = ReturnType<typeof openDatabase>;
