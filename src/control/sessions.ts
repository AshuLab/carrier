import { and, desc, eq, sql } from 'drizzle-orm';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { PanelAgent } from '../status/types.ts';
import type { CallerResult } from '../execution/caller-result.ts';
import { redact } from '../logging/redact.ts';
import { callerResults } from '../storage/caller-results.ts';
import type { SessionFailure, SessionResult, SessionsReply } from './replies.ts';

const MAX_SUMMARY = 1500;
const MAX_EVIDENCE = 600;
const MAX_REASON = 600;
const MAX_FAILURE_DETAIL = 300;

/** Text an agent wrote: redacted first, so a token is never cut into something the patterns no longer match, then cut. */
const safe = (text: string, max: number) => redact(text).slice(0, max);

function resultOf(raw: string | null): SessionResult | null {
  if (raw === null) return null;
  const parsed = JSON.parse(raw) as CallerResult;
  return {
    outcome: parsed.outcome,
    summary: safe(parsed.summary, MAX_SUMMARY),
    verification: parsed.outcome === 'completed' ? { ci: parsed.verification.ci, evidence: safe(parsed.verification.evidence, MAX_EVIDENCE) } : null,
    reason: parsed.outcome === 'needs_human' ? safe(parsed.reason, MAX_REASON) : null,
  };
}

function failureOf(row: typeof executions.$inferSelect): SessionFailure | null {
  if (row.failureKind === null) return null;
  const { failureKind: kind, failureDetail, exitCode, signal, hostFreeMemMb, hostLoad } = row;
  return { kind, detail: safe(failureDetail ?? '', MAX_FAILURE_DETAIL), exitCode, signal, hostFreeMemMb, hostLoad };
}

/** The configuration folder each harness runs with when its option names none: the engine's own environment (a path, never a secret). */
export type ConfigDirs = Partial<Record<PanelAgent['harness'], string>>;

/** The agent an execution ran with: its own row, or the epic's frozen configuration for a row written before it was recorded. */
export function agentOf(row: typeof executions.$inferSelect, config: typeof epics.$inferSelect.config): PanelAgent {
  const frozen = config?.agents[row.stage === 'review' ? 'reviewer' : 'author'];
  return {
    harness: (row.harness ?? frozen?.harness ?? 'claude') as PanelAgent['harness'],
    model: row.model ?? frozen?.model ?? '',
    provider: row.harness === null ? (frozen?.provider ?? null) : (row.provider as PanelAgent['provider']),
  };
}

/**
 * Every execution of an epic, newest first; null for an epic the engine does not know.
 * A session has a descriptor only once it is not running and its id and folder are known (ADR 0007); `configDir` is the folder the execution that wrote it ran with: its option's, else the engine environment's (`inherited`).
 */
export function sessionsOf(db: Db, repo: string, issue: number, inherited: ConfigDirs = {}): SessionsReply | null {
  const epic = db.select({ id: epics.id, config: epics.config }).from(epics).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).get();
  if (epic === undefined) return null;
  const rows = db
    .select({ row: executions, result: callerResults.result })
    .from(executions)
    .leftJoin(callerResults, eq(callerResults.executionId, executions.executionId))
    .where(eq(executions.epicId, epic.id))
    .orderBy(desc(executions.startedAt), sql`executions.rowid desc`)
    .all();
  return {
    sessions: rows.map(({ row, result }) => {
      const role = row.stage === 'review' ? 'reviewer' : 'author';
      const agent = agentOf(row, epic.config);
      const harness = agent.harness;
      const configDir = row.configDir ?? inherited[harness];
      const resume =
        row.status === 'running' || row.sessionId === null || row.workspace === null
          ? null
          : { harness, sessionId: row.sessionId, cwd: row.workspace, ...(configDir !== undefined && { configDir }) };
      return { executionId: row.executionId, stage: row.stage, role, round: row.round, agent, status: row.status, startedAt: row.startedAt, finishedAt: row.finishedAt, resume, result: resultOf(result), failure: failureOf(row) };
    }),
  };
}
