import { z } from 'zod';
import { repoNamePattern } from '../config/schema.ts';
import { projectNamePattern } from './projects.ts';

// Never a leading dash (it would be an option of git) nor whitespace.
const branch = z.string().min(1).max(1000).regex(/^[^-\s][^\s]*$/);
/** A new empty project (`git init` in the projects folder). Its `kind` stays `project` on the wire, since an older host refuses another value. */
export const newProjectKind = 'project';
const workspace = z.discriminatedUnion('kind', [
  z.strictObject({ kind: z.literal('folder'), folder: z.string().min(1) }),
  z.strictObject({ kind: z.literal('repo'), repo: z.string().regex(repoNamePattern) }),
  z.strictObject({ kind: z.literal(newProjectKind), name: z.string().regex(projectNamePattern) }),
]);

/** What a new session is before it exists: where it works, which agent, and the first message. The host prepares it when it is sent. */
export const plan = z
  .strictObject({
    workspace,
    agent: z.string().min(1),
    options: z.record(z.string(), z.string()).optional(),
    text: z.string().min(1),
    branch: branch.optional(),
    worktree: z.strictObject({ name: z.string().max(1000).optional(), startFrom: z.enum(['remote', 'local']).optional() }).optional(),
  })
  .refine((p) => p.workspace.kind !== newProjectKind || (p.branch === undefined && p.worktree === undefined)); // a new project has no commits

export type Plan = z.infer<typeof plan>;

export type Step = 'clone' | 'fetch' | 'project' | 'worktree' | 'checkout' | 'action' | 'agent' | 'message';
/** The moments a project's actions run at (ADR 0039). */
export type ActionWhen = 'afterClone' | 'newWorktree';
/** One transition of a step of a session's preparation. `detail` is the reason in words, never git's raw stderr. An `action` step names its action (`action`, cut) and the moment it runs at (`when`): each action is a step of its own. */
export type StepEvent = { kind: 'step'; step: Step; status: 'running' | 'done' | 'failed'; detail?: string; action?: string; when?: ActionWhen };
