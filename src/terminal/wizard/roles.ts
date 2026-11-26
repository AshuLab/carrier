/** The role slots `carrier init` asks, in the order a person meets them: the one table the blocks (and, later, the flags) are built from. `reviewer-2` to `reviewer-4` are the engine's names for the extra reviewers; the lead keeps the `lead-reviewer` the flags already have. */
export const roleSlots = ['author', 'reviewer', 'reviewer-2', 'reviewer-3', 'reviewer-4', 'lead-reviewer'] as const;

export type RoleSlot = (typeof roleSlots)[number];

/** How a slot reads in a question: `lead-reviewer` is the "lead reviewer". */
export const roleName = (slot: RoleSlot) => slot.replace(/-/g, ' ');

/** The key a slot has in a config and in the flags: `lead-reviewer` is `leadReviewer`. */
export const roleKey = (slot: RoleSlot) => slot.replace(/-([a-z0-9])/g, (_, next: string) => next.toUpperCase());

/** What the block's box says before its first question. */
export const roleBlurb = (slot: RoleSlot) =>
  slot === 'author'
    ? 'Writes the code of each epic and answers the reviewer.'
    : slot === 'lead-reviewer'
      ? 'A second, optional reviewer for architecture and production readiness.'
      : 'Reviews the pull request when the author is done.';
