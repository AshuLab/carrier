import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import { ConfigRefused, editBehavior, saveEngineConfig, setWatchedRepos } from './engine-edit.ts';
import { engineConfigPathOf } from './places.ts';
import { validEngineFile } from './testing.ts';

let folder: string;
let file: string;
beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), 'ee-'));
  file = engineConfigPathOf(folder);
  writeFileSync(file, JSON.stringify(validEngineFile, null, 2));
});
afterEach(() => rmSync(folder, { recursive: true, force: true }));
const written = () => JSON.parse(readFileSync(file, 'utf8'));
const refusal = (run: () => unknown) => {
  try {
    run();
  } catch (error) {
    if (error instanceof ConfigRefused) return error;
    throw error;
  }
  throw new Error('expected a refusal');
};

describe('setWatchedRepos', () => {
  test('keeps a repo that stays with its own fields, adds a new one as { name } and keeps every other key', () => {
    const result = setWatchedRepos(['acme/web', 'new/one'], file, folder);
    const { repos, ...rest } = validEngineFile;
    expect(written()).toEqual({ ...rest, repos: [validEngineFile.repos[1], { name: 'new/one' }] });
    expect(result).toEqual({ saved: { repos: [validEngineFile.repos[1], { name: 'new/one' }] } });
    expect(Object.keys(written())).toEqual(Object.keys(validEngineFile)); // the person's order
  });

  test('an empty list is fine: nothing is watched', () => {
    setWatchedRepos([], file, folder);
    expect(written().repos).toEqual([]);
  });

  test.each([
    ['a name that is not owner/name', ['AshuLab/carrier', 'nope'], 'nope must be owner/name', 'repos[1]', 'notARepo'],
    ['a name with a dot segment', ['a/..'], 'a/.. must be owner/name', 'repos[0]', 'notARepo'],
    ['a repo twice, ignoring case', ['a/b', 'A/B'], 'A/B is already watched', 'repos[1]', 'alreadyWatched'],
    ["two repos with one folder name (Solve's worktrees have no owner)", ['a/web', 'b/Web'], "b/Web has the same folder name as a/web; Solve's worktree paths have no owner", 'repos[1]', 'sameFolderName'],
  ])('%s is refused with the Watching page words, a code and its key path and kind, and the file stays as it was', (_what, repos, words, path, kind) => {
    const before = readFileSync(file, 'utf8');
    const refused = refusal(() => setWatchedRepos(repos, file, folder));
    expect([refused.message, refused.code, refused.params]).toEqual([words, 'config.problem', { path, problem: kind }]);
    expect(readFileSync(file, 'utf8')).toBe(before);
  });

  test.each([
    ['is not there', () => rmSync(file), 'notFound'],
    ['is not JSON', () => writeFileSync(file, '{ nope'), 'notJson'],
    ['is not an object', () => writeFileSync(file, '[]'), 'notAnObject'],
  ])('an engine.json that %s is refused and left as it is', (_what, spoil, kind) => {
    spoil();
    expect(refusal(() => setWatchedRepos(['a/b'], file, folder)).params).toEqual({ path: '(file)', problem: kind });
  });

  test('a result the whole schema refuses is refused, naming the key', () => {
    writeFileSync(file, JSON.stringify({ ...validEngineFile, orchestratorProfile: 'ghost' }));
    const before = readFileSync(file, 'utf8');
    expect(refusal(() => setWatchedRepos(['a/b'], file, folder)).params).toEqual({ path: 'orchestratorProfile', problem: 'invalid' });
    expect(readFileSync(file, 'utf8')).toBe(before);
  });
});

describe('editBehavior', () => {
  test('writes a value that is not the default, keeps the other keys of limits and every other key', () => {
    const result = editBehavior({ pollIntervalMinutes: 2.5, logLevel: 'debug', finishedWindowDays: 20, limits: { maxConcurrentEpics: 5, maxExecutionHours: 'unlimited', maxReviews: 7, maxLeadRounds: 4 } }, file, folder);
    expect(written()).toEqual({ ...validEngineFile, pollIntervalMinutes: 2.5, logLevel: 'debug', finishedWindowDays: 20, limits: { maxReviews: 7, maxLeadRounds: 4, maxConcurrentEpics: 5, maxExecutionHours: 'unlimited' } });
    expect(result).toEqual({ saved: { pollIntervalMinutes: 2.5, logLevel: 'debug', finishedWindowDays: 20, limits: { maxConcurrentEpics: 5, maxExecutionHours: 'unlimited', maxReviews: 7, maxLeadRounds: 4 } } });
  });

  test("a value equal to the engine's default is taken out of the file, and an emptied limits goes", () => {
    writeFileSync(file, JSON.stringify({ ...validEngineFile, logLevel: 'debug', limits: { maxReviews: 7, maxLeadRounds: 2 } }));
    const result = editBehavior({ pollIntervalMinutes: 5, logLevel: 'info', limits: { maxReviews: 5, maxLeadRounds: 3, maxExecutionHours: 4 } }, file, folder);
    expect(written()).toEqual({ ...validEngineFile, limits: undefined, logLevel: undefined });
    expect('limits' in written() || 'logLevel' in written() || 'pollIntervalMinutes' in written()).toBe(false);
    expect(result).toEqual({ saved: {} });
  });

  test.each([
    ['a poll interval of 0', { pollIntervalMinutes: 0 }, 'Must be more than 0', 'pollIntervalMinutes', 'tooSmall'],
    ['a log level that is not one', { logLevel: 'loud' }, 'Must be one of debug, info, warn, error', 'logLevel', 'notOneOf'],
    ['no concurrent epic', { limits: { maxConcurrentEpics: 0 } }, 'Must be 1 or more', 'limits.maxConcurrentEpics', 'tooSmall'],
    ['no review', { limits: { maxReviews: 0 } }, 'Must be 1 or more', 'limits.maxReviews', 'tooSmall'],
    ['no lead round', { limits: { maxLeadRounds: 0 } }, 'Must be 1 or more', 'limits.maxLeadRounds', 'tooSmall'],
    ['a negative retry count', { limits: { maxExecutionRetries: -1 } }, 'Must be 0 or more', 'limits.maxExecutionRetries', 'tooSmall'],
    ['no hour', { limits: { maxExecutionHours: 0 } }, 'Must be 1 or more, or unlimited', 'limits.maxExecutionHours', 'tooSmall'],
    ['a timeout of 0', { limits: { githubCallTimeoutSeconds: 0 } }, 'Must be 1 or more', 'limits.githubCallTimeoutSeconds', 'tooSmall'],
    ['31 days', { finishedWindowDays: 31 }, 'Must be a whole number from 1 to 30', 'finishedWindowDays', 'outOfRange'],
    ['half a review', { limits: { maxReviews: 2.5 } }, 'Must be a whole number', 'limits.maxReviews', 'notWhole'],
    ['half a lead round', { limits: { maxLeadRounds: 1.5 } }, 'Must be a whole number', 'limits.maxLeadRounds', 'notWhole'],
  ])('%s is refused with the Behavior page words, a code and its key path and kind, and the file stays as it was', (_what, changes, words, path, kind) => {
    const before = readFileSync(file, 'utf8');
    const refused = refusal(() => editBehavior(changes, file, folder));
    expect([refused.message, refused.code, refused.params]).toEqual([words, 'config.problem', { path, problem: kind }]);
    expect(readFileSync(file, 'utf8')).toBe(before);
  });
});

describe('saveEngineConfig', () => {
  test('writes the whole file in a folder that is not there yet, and leaves no temporary file', () => {
    const target = join(folder, 'new', 'engine.json');
    saveEngineConfig(validEngineFile, target, folder);
    expect(JSON.parse(readFileSync(target, 'utf8'))).toEqual(validEngineFile);
    expect(readdirSync(join(folder, 'new'))).toEqual(['engine.json']);
  });

  test('a config the engine would refuse is not written and the file that was there stays as it was', () => {
    const before = readFileSync(file, 'utf8');
    const refused = refusal(() => saveEngineConfig({ ...validEngineFile, limits: { maxReviews: 0 } }, file, folder));
    expect(refused.code).toBe('config.problem');
    expect(readFileSync(file, 'utf8')).toBe(before);
    expect(readdirSync(folder)).toEqual(['engine.json']);
  });
});
