/** The role slots `carrier init` asks and has flags for, in the order a person meets them: the one table the blocks and the flags are built from. The extra reviewers are not slots: each has the name its person gives it and no flags of its own yet; the lead keeps the `lead-reviewer` the flags already have. */
export const roleSlots = ['author', 'reviewer', 'lead-reviewer'] as const;

export type RoleSlot = (typeof roleSlots)[number];

/** What one block of questions is about: a slot, or an extra reviewer. Its questions call it "extra reviewer" and never by its name, because the journal knows a question by its words and a new name must keep the answers already given. */
export type Block = RoleSlot | 'extra-reviewer';

/** The most extra reviewers a config holds. */
export const maxExtraReviewers = 3;

/** How a block reads in a question: `lead-reviewer` is the "lead reviewer". */
export const roleName = (block: Block) => block.replace(/-/g, ' ');

/** A flag name as the key it has in `InitFlags`: `lead-reviewer-effort` is `leadReviewerEffort`. */
export const camel = (name: string) => name.replace(/-([a-z0-9])/g, (_, next: string) => next.toUpperCase());

export type Camel<S extends string> = S extends `${infer Head}-${infer Tail}` ? `${Head}${Capitalize<Camel<Tail>>}` : S;

/** The key a block has in the flags and in the roles of a config: `lead-reviewer` is `leadReviewer`. An extra reviewer has no flags, and its key in the config is derived from its name. */
export const roleKey = (block: Block) => camel(block);

/** What follows `--<role>` in the flags that take one text: the role's `<harness>:<model>` itself, its GitHub profile, local provider, effort and persona. `-failover` is the one that repeats. */
export const roleFlagSuffixes = ['', '-profile', '-provider', '-effort', '-persona-name', '-persona-prompt'] as const;

/** What the block's box says before its first question. */
export const roleBlurb = (slot: Block) =>
  slot === 'author'
    ? 'Writes the code of each epic and answers the reviewer.'
    : slot === 'lead-reviewer'
      ? 'A second, optional reviewer for architecture and production readiness.'
      : 'Reviews the pull request when the author is done.';
