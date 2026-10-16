import { callerResults } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { parseCallerResult, type CallerResult, type Expected, type ParseOutcome } from './caller-result.ts';

type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];

/**
 * Validates the result, stores it and runs `transition` in one transaction: if `transition` throws,
 * neither is kept. Importing the same executionId again changes nothing and skips `transition`.
 */
export function importResult(
  db: Db,
  raw: string | null,
  expected: Expected,
  transition: (tx: Tx, result: CallerResult) => void,
): ParseOutcome & { duplicate?: true } {
  const parsed = parseCallerResult(raw, expected);
  if (!parsed.ok) return parsed;
  return db.transaction((tx) => {
    const { result } = parsed;
    const inserted = tx
      .insert(callerResults)
      .values({ executionId: result.executionId, outcome: result.outcome, result: JSON.stringify(result) })
      .onConflictDoNothing()
      .run();
    if (inserted.changes === 0) return { ...parsed, duplicate: true as const };
    transition(tx, result);
    return parsed;
  });
}
