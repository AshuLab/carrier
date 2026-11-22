import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { FakeClock } from '../orchestration/fake.ts';
import { createDisk, measureWithDu, type ProjectDisk } from './disk.ts';
import { openChatDatabase } from './db.ts';
import type { Git } from './git.ts';

// The size cache and the scheduling of the measures, with a fake clock, a fake measurer and a git that lists the worktrees it is told to.
let root: string;
let clock: FakeClock;
let db: ReturnType<typeof openChatDatabase>;
let app: string;
let other: string;
let worktree: string;
beforeEach(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'disk-')));
  vi.stubEnv('CARRIER_HOME', root);
  clock = new FakeClock();
  clock.time = 1_000;
  db = openChatDatabase(join(root, 'chat.db'));
  app = join(root, 'projects', 'app');
  other = join(root, 'projects', 'other');
  worktree = join(root, 'chat', 'worktrees', 'acme', 'app', 'kerrigan');
  for (const folder of [app, other, worktree]) mkdirSync(folder, { recursive: true });
});
afterEach(() => {
  db.$client.close();
  rmSync(root, { recursive: true, force: true });
  vi.unstubAllEnvs();
});

/** `git worktree list` for `app` says its worktree, a folder outside `worktrees/` and one that is gone; any other folder is not a repository. */
const git: Git = {
  sshHost: async (host) => host,
  run: async (folder) => (folder === app ? { ok: true, out: `worktree ${app}\nbranch refs/heads/main\n\nworktree ${worktree}\nbranch refs/heads/carrier/kerrigan\n\nworktree ${other}\nbranch refs/heads/x\n\nworktree ${join(root, 'chat', 'worktrees', 'acme', 'app', 'gone')}\nbranch refs/heads/y\n` } : { ok: false, code: 128, stderr: 'fatal: not a git repository' }),
};

/** A measurer that answers `sizes` by folder, one measure at a time, and says how many ran together. */
function measurer(sizes: Record<string, number>) {
  const measured: string[] = [];
  let together = 0;
  let most = 0;
  const measure = vi.fn(async (folder: string) => {
    measured.push(folder);
    most = Math.max(most, ++together);
    await new Promise((resolve) => setTimeout(resolve, 1));
    together--;
    return sizes[folder] ?? 1;
  });
  return { measure, measured, most: () => most };
}
const settled = async (ask: () => ProjectDisk) => await vi.waitFor(() => expect(ask().measuring).toEqual([]));

test('a project never measured has no figure, and a stale ask measures its folder and the worktrees under worktrees/, keeping each part', async () => {
  const { measure, measured } = measurer({ [app]: 1000, [worktree]: 5000 });
  const disk = createDisk({ db, clock, git, measure });
  const ask = () => disk.projectDisk({ folders: [app] });
  expect(ask()).toEqual({ projects: [{ folder: app, bytes: null, measuredAt: null, parts: {} }], measuring: [] });
  expect(disk.projectDisk({ folders: [app], refresh: 'stale' }).measuring).toEqual([app]);
  await settled(ask);
  expect(measured).toEqual([app, worktree]);
  expect(ask().projects).toEqual([{ folder: app, bytes: 6000, measuredAt: 1_000, parts: { [app]: 1000, [worktree]: 5000 } }]);
});

test('a project that is not a repository is its own folder', async () => {
  const { measure, measured } = measurer({ [other]: 70 });
  const disk = createDisk({ db, clock, git, measure });
  disk.projectDisk({ folders: [other], refresh: 'stale' });
  await settled(() => disk.projectDisk({ folders: [other] }));
  expect(measured).toEqual([other]);
  expect(disk.projectDisk({ folders: [other] }).projects[0]).toMatchObject({ bytes: 70, parts: { [other]: 70 } });
});

test('a figure under a day old is not measured again by a stale ask, one a day old is, and now measures it whatever its age', async () => {
  const { measure, measured } = measurer({});
  const disk = createDisk({ db, clock, git, measure });
  const ask = (refresh?: 'stale' | 'now') => disk.projectDisk({ folders: [other], refresh });
  ask('stale');
  await settled(ask);
  clock.time += 86_400_000 - 1;
  ask('stale');
  expect(measured).toHaveLength(1);
  ask('now');
  await settled(ask);
  expect(measured).toHaveLength(2);
  clock.time += 86_400_000;
  ask('stale');
  await settled(ask);
  expect(measured).toHaveLength(3);
  expect(ask().projects[0]!.measuredAt).toBe(clock.time);
});

test('the projects are measured one at a time, each queued once, and the last known figure is answered while one is measured again', async () => {
  const { measure, measured, most } = measurer({ [other]: 9 });
  const disk = createDisk({ db, clock, git, measure });
  const folders = [other, app];
  expect(disk.projectDisk({ folders, refresh: 'stale' }).measuring).toEqual(folders);
  expect(disk.projectDisk({ folders, refresh: 'stale' }).measuring).toEqual(folders); // asked again while they wait: not queued twice
  await settled(() => disk.projectDisk({ folders }));
  expect(measured).toEqual([other, app, worktree]);
  expect(most()).toBe(1);
  const measuring = disk.projectDisk({ folders: [other], refresh: 'now' });
  expect(measuring).toMatchObject({ projects: [{ bytes: 9 }], measuring: [other] });
  await settled(() => disk.projectDisk({ folders: [other] }));
});

test('a folder that is gone or that Carrier never works in has no figure and is not measured', async () => {
  const { measure } = measurer({});
  const disk = createDisk({ db, clock, git, measure });
  const inside = join(root, 'engine');
  mkdirSync(inside, { recursive: true });
  expect(disk.projectDisk({ folders: [join(root, 'gone'), 'relative', inside], refresh: 'now' })).toEqual({ projects: [], measuring: [] });
  expect(measure).not.toHaveBeenCalled();
});

test('a measure that fails is logged and leaves the last figure, and the next project is measured', async () => {
  const measure = vi.fn(async (folder: string) => {
    if (folder === other) throw new Error('boom');
    return 5;
  });
  const disk = createDisk({ db, clock, git, measure });
  const folders = [other, join(root, 'projects')];
  disk.projectDisk({ folders, refresh: 'now' });
  await settled(() => disk.projectDisk({ folders }));
  expect(disk.projectDisk({ folders }).projects.map((entry) => entry.bytes)).toEqual([null, 5]);
});

test('the figures are in chat.db, so a host that starts again knows them, and a lost file only means measuring again', async () => {
  const first = createDisk({ db, clock, git, measure: measurer({ [other]: 321 }).measure });
  first.projectDisk({ folders: [other], refresh: 'stale' });
  await settled(() => first.projectDisk({ folders: [other] }));
  db.$client.close();
  db = openChatDatabase(join(root, 'chat.db'));
  expect(createDisk({ db, clock, git, measure: measurer({}).measure }).projectDisk({ folders: [other] }).projects[0]).toMatchObject({ bytes: 321, measuredAt: 1_000 });
  db.$client.close();
  rmSync(join(root, 'chat.db'));
  db = openChatDatabase(join(root, 'chat.db'));
  expect(createDisk({ db, clock, git, measure: measurer({}).measure }).projectDisk({ folders: [other] }).projects[0]).toMatchObject({ bytes: null, measuredAt: null });
});

test('stop ends the measure that runs and writes nothing after it', async () => {
  let release = () => {};
  const measure = vi.fn(async (_folder: string, signal: AbortSignal) => {
    await new Promise<void>((resolve) => ((release = resolve), signal.addEventListener('abort', () => resolve(), { once: true })));
    return 5;
  });
  const disk = createDisk({ db, clock, git, measure });
  disk.projectDisk({ folders: [other, join(root, 'projects')], refresh: 'now' });
  await vi.waitFor(() => expect(measure).toHaveBeenCalledTimes(1));
  disk.stop();
  release();
  await vi.waitFor(() => expect(disk.projectDisk({ folders: [other] }).measuring).toEqual([]));
  expect(measure).toHaveBeenCalledTimes(1);
  expect(db.$client.prepare('select count(*) as n from project_sizes').get()).toEqual({ n: 0 });
});

test('du measures a real folder as the blocks it takes', async () => {
  writeFileSync(join(other, 'big.bin'), Buffer.alloc(300_000, 1));
  const bytes = await measureWithDu(other, new AbortController().signal);
  expect(bytes).toBeGreaterThanOrEqual(300_000);
  expect(bytes).toBeLessThan(600_000);
  await expect(measureWithDu(join(root, 'nothing-here'), new AbortController().signal)).rejects.toThrow();
});
