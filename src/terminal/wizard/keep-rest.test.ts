import { join, resolve } from 'node:path';
import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../config/load.ts';
import { Cancelled } from '../prompts/types.ts';
import { asFiles, fakeDeps, providersWritten, quietUi, useTempDir } from './testing.ts';
import { runInit } from './wizard.ts';

// What `init` keeps of a file it did not make: an edit writes over only the keys the wizard asks, and nothing is replaced before the person knows why.

const dir = useTempDir();
const folder = join(dir, 'home');
const engine = join(folder, 'engine.json');
const existingKey = `A config already exists at ${engine}`;
const reposKey = 'Repos to watch (owner/name, comma separated, or none for now)';
const notNow = 'Start Carrier now?';

// A file with every setting the wizard does not ask, next to the ones it does.
const rich = {
  pollIntervalMinutes: 7,
  logLevel: 'debug',
  finishedWindowDays: 9,
  labels: { epic: 'e', ready: 'r', running: 'ru', readyForTest: 'rt', needsHuman: 'nh' },
  limits: { maxReviews: 7, maxLeadRounds: 2 },
  skills: { ship: 'my-ship', review: { review: 'my-review', publish: null }, fix: 'my-fix' },
  repos: [{ name: 'X/y', skills: { ship: 'own-ship' }, agents: { author: { model: 'opus' } } }, { name: 'X/z' }],
  profiles: { 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' }, gh: { kind: 'gh' } },
  orchestratorProfile: 'tassadar-agent',
  failover: { triggers: ['usage_limit'], roles: { author: [{ provider: 'codex', model: 'gpt-test' }] } },
  agents: {
    author: { profile: 'tassadar-agent', provider: 'claude', model: 'opus', skills: { ship: 'role-ship' } },
    reviewer: { profile: 'gh', provider: 'codex', model: 'gpt-test' },
    leadReviewer: { profile: 'gh', provider: 'claude', model: 'opus', skills: { lead: { review: 'lead-review' } } },
    extraReviewers: [{ profile: 'gh', provider: 'codex', model: 'gpt-x' }],
  },
};
const accounts = { claude: { harness: 'claude' }, codex: { harness: 'codex' } };
const files = (engineFile: Record<string, unknown>) => asFiles({ providers: accounts, ...engineFile });

// Enter everywhere, except what a test answers.
const run = async (engineFile: Record<string, unknown>, answers: Record<string, string | boolean | (string | boolean)[]>, flags: Parameters<typeof runInit>[0] = {}) => {
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: files(engineFile) });
  const { ui, asked } = quietUi({ [reposKey]: 'X/y, new/repo', [notNow]: false, ...answers });
  try {
    const result = await runInit(flags, ui, deps, folder);
    return { written: JSON.parse(written[flags.out === undefined ? engine : resolve(flags.out)]!), providers: providersWritten(written, folder), asked, result };
  } catch (error) {
    if (error instanceof Cancelled) return { written: undefined, asked, files: written };
    throw error;
  }
};

test('an edit with one answer changed keeps every setting the wizard does not ask', async () => {
  const { written } = await run(rich, { 'Model and effort: opus, change it?': true, 'Model for the author': 'sonnet' });
  expect(written.agents.author).toEqual({ profile: 'tassadar-agent', provider: 'claude', model: 'sonnet', skills: { ship: 'role-ship' } }); // the model is the one change, the role's skills stay
  expect(written.agents.leadReviewer.skills).toEqual({ lead: { review: 'lead-review' } });
  expect(written.agents.extraReviewers).toEqual(rich.agents.extraReviewers);
  for (const key of ['pollIntervalMinutes', 'logLevel', 'finishedWindowDays', 'labels', 'limits', 'skills'] as const) expect(written[key]).toEqual(rich[key]);
  expect(written.failover).toEqual(rich.failover);
  expect(Object.keys(written)).toEqual(Object.keys(rich).filter((key) => key !== 'failover').concat('failover')); // nothing added, nothing lost
  expect(loadConfig(defaults, written, accounts as never).ok).toBe(true); // what the engine would load
});

test('a repo that stays keeps its entry, one that is left out is gone, a new one is { name }', async () => {
  const { written } = await run(rich, {});
  expect(written.repos).toEqual([rich.repos[0], { name: 'new/repo' }]);
});

test('a lead reviewer the person declines is removed from the file, and the failover the person drops goes with its role only', async () => {
  const withReviewerFailover = { ...rich, failover: { triggers: ['usage_limit'], roles: { reviewer: [{ provider: 'claude', model: 'sonnet' }] } } };
  const { written } = await run(withReviewerFailover, { 'Add a lead reviewer?': false, 'Keep the failover you have? reviewer: claude sonnet': false });
  expect(written.agents).not.toHaveProperty('leadReviewer');
  expect(written.agents.extraReviewers).toEqual(rich.agents.extraReviewers);
  expect(written.failover).toEqual({ triggers: ['usage_limit'] }); // the triggers are the file's, the role's steps were declined
});

test('"Start over" writes the same file whole from the answers, holding none of what the wizard does not ask', async () => {
  const { written } = await run(rich, { [existingKey]: 'fresh' });
  for (const key of ['pollIntervalMinutes', 'logLevel', 'finishedWindowDays', 'labels', 'limits', 'skills'] as const) expect(written).not.toHaveProperty(key);
  expect(written.agents).not.toHaveProperty('extraReviewers');
  expect(written.agents.author).not.toHaveProperty('skills');
  expect(written.repos).toEqual([{ name: 'X/y' }, { name: 'new/repo' }]); // no override of the old X/y
});

test('--out to another file is written whole as well', async () => {
  const out = join(dir, 'other.json');
  const { written } = await run(rich, { [`${out} exists. Overwrite it?`]: true }, { out });
  expect(written).not.toHaveProperty('limits');
  expect(written.agents).not.toHaveProperty('extraReviewers');
});

// A file that does not validate: its first error is shown, and nothing is written until the person answers.
const broken = { ...rich, mystery: 1 };

test('an existing config that does not validate shows its first error and asks, writing nothing until answered', async () => {
  const left = await run(broken, {});
  expect(left.asked.find((line) => line.startsWith('warn:'))).toMatch(/^warn:.*engine\.json does not validate, first error: .*mystery/);
  expect(left.asked).toContain('What do you want to do with it?');
  expect(left.written).toBeUndefined(); // the default answer is to leave it
  expect(left.files).toEqual({});
  const replaced = await run(broken, { 'What do you want to do with it?': 'fresh' });
  expect(replaced.written).not.toHaveProperty('mystery');
  expect(replaced.written).not.toHaveProperty('limits');
});

test('--yes still replaces a config that does not validate, and says its first error', async () => {
  const { written, asked } = await run(broken, {}, { yes: true, repo: ['A/b'] });
  expect(asked.find((line) => line.startsWith('warn:'))).toMatch(/does not validate and is replaced, first error: .*mystery/);
  expect(written).not.toHaveProperty('mystery');
  expect(written.repos).toEqual([{ name: 'A/b' }]);
});
