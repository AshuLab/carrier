// Feeds the stdout.log of an old Claude execution through the adapter (ADR 0006): prints its events as JSON lines,
// or, with --db and --execution, stores them for an execution that ran before events existed.
//   pnpm replay:events <stdout.log> [--db <carrier.db> --execution <id>]
import { existsSync, readFileSync, statSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { eq } from 'drizzle-orm';
import { createEventState, type AgentEvent } from '../execution/events.ts';
import { openDatabase } from '../storage/db.ts';
import { executionEvents, recordEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { parseClaudeEvents } from './claude.ts';

export function replayEvents(log: string): AgentEvent[] {
  const state = createEventState();
  return log.split('\n').flatMap((line) => parseClaudeEvents(line, state));
}

class UsageError extends Error {}

function run(argv: string[], out: (line: string) => void): void {
  const { values, positionals } = parseArgs({ args: argv, options: { db: { type: 'string' }, execution: { type: 'string' } }, allowPositionals: true });
  const [file, ...extra] = positionals;
  if (file === undefined || extra.length > 0 || (values.db === undefined) !== (values.execution === undefined)) {
    throw new UsageError('usage: replay-events <stdout.log> [--db <carrier.db> --execution <id>]');
  }
  if (!existsSync(file)) throw new Error(`cannot read ${file}: no such file`);
  const events = replayEvents(readFileSync(file, 'utf8'));
  if (values.db === undefined || values.execution === undefined) {
    for (const event of events) out(JSON.stringify(event));
    return;
  }
  if (!existsSync(values.db)) throw new Error(`cannot open ${values.db}: no such file`); // openDatabase would create an empty one
  const db = openDatabase(values.db);
  try {
    if (!db.select().from(executions).where(eq(executions.executionId, values.execution)).get()) throw new Error(`no execution ${values.execution} in ${values.db}`);
    if (db.select().from(executionEvents).where(eq(executionEvents.executionId, values.execution)).limit(1).get()) {
      throw new Error(`execution ${values.execution} already has events: nothing was stored`);
    }
    // The log has no time for most lines: the time the log was last written is the closest there is.
    recordEvents(db, values.execution, events, statSync(file).mtimeMs);
    out(`stored ${events.length} events for ${values.execution}`);
  } finally {
    db.$client.close();
  }
}

if (import.meta.main) {
  try {
    run(process.argv.slice(2), (line) => console.log(line));
  } catch (e) {
    console.error(`replay-events: ${e instanceof Error ? e.message : String(e)}`);
    process.exit(e instanceof UsageError ? 2 : 1);
  }
}
