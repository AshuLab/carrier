import type { Config } from './schema.ts';

/** What a stage runs when the person names nothing: Solve's own skills. */
export const solveSkills = { ship: 'ship', review: { review: 'code-review', publish: 'code-post' }, fix: 'code-resolve' } as const;

/** `named` is true when the person wrote the skill at some level of the config, false when it is Solve's default. */
export type StageSkill = { name: string; named: boolean };
export type ReviewSkills = { review: StageSkill; publish: StageSkill | null };
/** `lead` is the lead reviewer's, saved only when the epic has one; an epic saved before it existed has none. */
export type ResolvedSkills = { ship: StageSkill; review: ReviewSkills; fix: StageSkill; lead?: ReviewSkills };

type ReviewLevel = { review?: string; publish?: string | null };
/** A level of the config that may name some of the skills: a repo's, or a role's own. */
export type SkillsLevel = { ship?: string; review?: ReviewLevel; lead?: ReviewLevel; fix?: string };

export const defaultSkills: ResolvedSkills = {
  ship: { name: solveSkills.ship, named: false },
  review: { review: { name: solveSkills.review.review, named: false }, publish: { name: solveSkills.review.publish, named: false } },
  fix: { name: solveSkills.fix, named: false },
};

/**
 * The skill of each stage: the last of `overrides` that names it wins, then `global`, then Solve's defaults.
 * Pass the levels from the weakest to the strongest: the repo's, the global roles', the repo's roles'.
 * `global` always holds a value (the loader merges the defaults in), so a global one that differs from Solve's is the only one that counts as named.
 */
export function resolveSkills(global: Config['skills'], ...overrides: (SkillsLevel | undefined)[]): ResolvedSkills {
  const levels = overrides.filter((level) => level !== undefined).reverse();
  const pick = <T>(of: (level: SkillsLevel) => T | undefined, base: T): { value: T; named: boolean } => {
    for (const level of levels) {
      const value = of(level);
      if (value !== undefined) return { value, named: true };
    }
    const own = of(global as SkillsLevel);
    const value = own === undefined ? base : own;
    return { value, named: value !== base };
  };
  const stage = (of: (level: SkillsLevel) => string | undefined, base: string): StageSkill => {
    const { value, named } = pick(of, base);
    return { name: value, named };
  };
  const publish = pick((level) => level.review?.publish, solveSkills.review.publish as string | null);
  return {
    ship: stage((level) => level.ship, solveSkills.ship),
    review: {
      review: stage((level) => level.review?.review, solveSkills.review.review),
      publish: publish.value === null ? null : { name: publish.value, named: publish.named },
    },
    fix: stage((level) => level.fix, solveSkills.fix),
  };
}

/**
 * The review skills of the lead (`stage` `lead`) or of an extra reviewer (`review`).
 * `own` are the levels of the role's own entry, from the weakest to the strongest; then the repo's and the global `skills.lead` (the lead only), then the repo's and the global `skills.review`, never another role's own skills, then Solve's defaults.
 * `global.review` always holds a value (the loader merges the defaults in), so only one that differs from Solve's counts as named; any other level was written by the person.
 */
export function resolveReviewSkills(stage: 'review' | 'lead', global: Config['skills'], repo: SkillsLevel | undefined, ...own: (ReviewLevel | undefined)[]): ReviewSkills {
  const levels: { level: ReviewLevel | undefined; written: boolean }[] = [
    ...own.reverse().map((level) => ({ level, written: true })),
    ...(stage === 'lead' ? [{ level: repo?.lead, written: true }, { level: global.lead, written: true }] : []),
    { level: repo?.review, written: true },
    { level: global.review, written: false },
  ];
  const pick = <T extends string | null>(of: (level: ReviewLevel) => T | undefined, base: T): { value: T; named: boolean } => {
    for (const { level, written } of levels) {
      const value = level === undefined ? undefined : of(level);
      if (value !== undefined) return { value, named: written || value !== base };
    }
    return { value: base, named: false };
  };
  const review = pick((level) => level.review, solveSkills.review.review as string);
  const publish = pick((level) => level.publish, solveSkills.review.publish as string | null);
  return { review: { name: review.value, named: review.named }, publish: publish.value === null ? null : { name: publish.value, named: publish.named } };
}

/** The skills saved with an epic; an epic saved before they existed has none and reads Solve's, none of them named. */
export const savedSkills = (config: { skills?: ResolvedSkills } | null): ResolvedSkills => config?.skills ?? defaultSkills;
