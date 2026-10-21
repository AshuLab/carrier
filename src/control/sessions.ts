import { and, desc, eq, sql } from 'drizzle-orm';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { PanelAgent } from '../status/types.ts';
import type { SessionsReply } from './replies.ts';

/** The configuration folder each harness ran with, when the engine's environment set one (a path, never a secret). */
export type ConfigDirs = Partial<Record<PanelAgent['harness'], string>>;

/**
 * Every execution of an epic, newest first; null for an epic the engine does not know.
 * The agent comes from the execution's own row, or from the epic's frozen configuration for a row written before it was recorded.
 * A session has a descriptor only once it is not running and its id and folder are known (ADR 0007).
 */
export function sessionsOf(db: Db, repo: string, issue: number, configDirs: ConfigDirs): SessionsReply | null {
  const epic = db.select({ id: epics.id, config: epics.config }).from(epics).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).get();
  if (epic === undefined) return null;
  const rows = db.select().from(executions).where(eq(executions.epicId, epic.id)).orderBy(desc(executions.startedAt), sql`rowid desc`).all();
  return {
    sessions: rows.map((row) => {
      const role = row.stage === 'review' ? 'reviewer' : 'author';
      const frozen = epic.config?.agents[role];
      const harness = (row.harness ?? frozen?.harness ?? 'claude') as PanelAgent['harness'];
      const agent: PanelAgent = {
        harness,
        model: row.model ?? frozen?.model ?? '',
        provider: row.harness === null ? (frozen?.provider ?? null) : (row.provider as PanelAgent['provider']),
      };
      const configDir = configDirs[harness];
      const resume =
        row.status === 'running' || row.sessionId === null || row.workspace === null
          ? null
          : { harness, sessionId: row.sessionId, cwd: row.workspace, ...(configDir !== undefined && { configDir }) };
      return { executionId: row.executionId, stage: row.stage, role, round: row.round, agent, status: row.status, startedAt: row.startedAt, finishedAt: row.finishedAt, resume };
    }),
  };
}
