import type { Config } from './schema.ts';

/** What a stage runs when the person names nothing: Solve's own skills. */
export const solveSkills = { ship: 'ship', review: { review: 'code-review', publish: 'code-post' }, fix: 'code-resolve' } as const;

/** `named` is true when the person wrote the skill at some level of the config, false when it is Solve's default. */
export type StageSkill = { name: string; named: boolean };
export type ResolvedSkills = { ship: StageSkill; review: { review: StageSkill; publish: StageSkill | null }; fix: StageSkill };

/** A level of the config that may name some of the skills: a repo's, or a role's own. */
export type SkillsLevel = { ship?: string; review?: { review?: string; publish?: string | null }; fix?: string };

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

/** The skills saved with an epic; an epic saved before they existed has none and reads Solve's, none of them named. */
export const savedSkills = (config: { skills?: ResolvedSkills } | null): ResolvedSkills => config?.skills ?? defaultSkills;
