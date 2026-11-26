/** A key or a type of an extra reviewer: a slug of 1 to 40 characters that starts with a letter, so no key reads as a number and the order of the file holds. */
export const slugPattern = /^[a-z][a-z0-9-]{0,39}$/;

export const maxSlugLength = 40;
/** The longest name an extra reviewer has, one line; it is the key's length too, so a key cut from a name loses nothing of a name that fits. */
export const maxNameLength = 40;

/** What a key cannot be: the words the file already uses for a role, and the two slots of a round that are not an extra reviewer's. */
export const reservedKeys = ['author', 'reviewer', 'lead', 'lead-reviewer'] as const;

/**
 * The key an extra reviewer gets from its name, never typed: lowercase, accents removed, every run of characters that are not a letter or a digit one hyphen,
 * hyphens trimmed from the ends, `r-` in front when it does not start with a letter, `extra` when nothing is left, cut so the key (suffix included) is at most 40 characters,
 * and `-2`, `-3`... while it is in `taken` or is a reserved word. The one rule for `carrier init` and for the request that adds a reviewer.
 */
export function extraReviewerKey(name: string, taken: Iterable<string> = []): string {
  const used = new Set(taken);
  const slug = name
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  const base = slug === '' ? 'extra' : /^[a-z]/.test(slug) ? slug : `r-${slug}`;
  for (let n = 1; ; n++) {
    const suffix = n === 1 ? '' : `-${n}`;
    const key = `${base.slice(0, maxSlugLength - suffix.length)}${suffix}`;
    if (!used.has(key) && !(reservedKeys as readonly string[]).includes(key)) return key;
  }
}
