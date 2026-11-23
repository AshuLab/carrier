import type { HarnessName } from './names.ts';
import type { SkillAnswer, Skills } from './skills.ts';

/** The skills port for tests: answers `present` unless told otherwise, and records what it was asked. */
export class FakeSkills implements Skills {
  /** What `has` answers, by skill name; a name not listed is `present`. */
  answers: Record<string, SkillAnswer> = {};
  asked: { harness: HarnessName; configDir: string | undefined; folder: string; name: string }[] = [];
  async has(harness: HarnessName, configDir: string | undefined, folder: string, name: string) {
    this.asked.push({ harness, configDir, folder, name });
    return this.answers[name] ?? 'present';
  }
}
