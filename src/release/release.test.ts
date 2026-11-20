import { execFileSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

// The release has no unit seam of its own (docs/specs/carrier-updates-itself.md): its seam is the workflow's dry run. These tests cover what the dry run cannot,
// the order of the publishing as the workflow states it and the two scripts that decide what is published and what the cask declares.
const scripts = join(import.meta.dirname, '../../.github/scripts');
const workflow = readFileSync(join(import.meta.dirname, '../../.github/workflows/release.yml'), 'utf8');
const seed = join(import.meta.dirname, '../../.github/homebrew/carrier-cask.rb');

// The workflow's jobs by id, each with its `needs` and its steps. Read as text: there is no YAML parser in the project and the file's layout is fixed.
const jobs = Object.fromEntries(
  workflow
    .slice(workflow.indexOf('\njobs:\n') + 7)
    .split(/\n(?=  [a-z][\w-]*:\n)/)
    .filter((text) => /^ {2}[a-z][\w-]*:$/m.test(text))
    .map((text) => {
      const body = text.includes('    steps:') ? text.slice(text.indexOf('    steps:')) : '';
      return [
        /^ {2}([a-z][\w-]*):$/m.exec(text)?.[1] ?? '',
        {
          needs: /^ {4}needs: \[?([^\]\n]*)\]?$/m.exec(text)?.[1]?.split(', ') ?? [],
          steps: body
            .split(/\n {6}- /)
            .slice(1)
            .map((step) => ({
              name: /^(?:uses: .*\n\s+)?name: (.*)$/m.exec(step)?.[1] ?? '',
              guarded: step.includes("if: env.DRY_RUN != 'true'"),
              text: step,
            })),
        },
      ];
    }),
);
const release = jobs['release'];

describe('release.yml', () => {
  it('publishes in the order npm, draft, tap, appcast, publish and no other', () => {
    const published = Object.entries(jobs).flatMap(([job, { steps }]) => steps.filter((step) => step.guarded).map((step) => `${job}: ${step.name}`));
    expect(published).toEqual([
      'formula: Tap',
      'npm: Publish to npm',
      'release: Tap',
      'release: GitHub Release as a draft',
      'release: Push the formula and the cask to the tap',
      'release: Attach the appcast',
      'release: Publish the release',
    ]);
  });

  it('waits for every other job before the draft, the tap and the feed', () => {
    expect(release?.needs.toSorted()).toEqual(Object.keys(jobs).filter((job) => job !== 'release').toSorted());
  });

  it('holds npm back for the engine checks and the formula, and not for the app', () => {
    expect(jobs['npm']?.needs.toSorted()).toEqual(['formula', 'pack', 'verify']);
  });

  it('decides the dry run once, for every job', () => {
    expect(workflow).toMatch(/^env:\n(?: {2}.*\n)*? {2}DRY_RUN: /m);
  });

  it('keeps every step that publishes, drafts included, out of a dry run', () => {
    const publishing = /gh release|github-release\.sh|pnpm publish|npm publish|git push/;
    const unguarded = Object.entries(jobs).flatMap(([job, { steps }]) =>
      steps.filter((step) => !step.guarded && publishing.test(step.text.replace(/^ *#.*$/gm, ''))).map((step) => `${job}: ${step.name}`),
    );
    expect(unguarded).toEqual([]);
  });

  it('checks the cask with the cask step before the Release is drafted', () => {
    const names = (release?.steps ?? []).map((step) => step.name);
    expect(names.indexOf('Cask')).toBeGreaterThanOrEqual(0);
    expect(names.indexOf('Cask')).toBeLessThan(names.indexOf('GitHub Release as a draft'));
    expect(release?.steps[names.indexOf('Cask')]?.text).toContain('cask.mjs ensure cask/carrier.rb');
  });
});

describe('github-release.sh', () => {
  // A gh that records its calls; `release view` answers from FAKE_RELEASE_EXISTS.
  function run(args: string[], exists: boolean) {
    const dir = mkdtempSync(join(tmpdir(), 'gh-'));
    const log = join(dir, 'calls.log');
    writeFileSync(join(dir, 'gh'), `#!/bin/sh\necho "$*" >> "$FAKE_LOG"\n[ "$1 $2" != "release view" ] || [ "$FAKE_RELEASE_EXISTS" = yes ]\n`);
    chmodSync(join(dir, 'gh'), 0o755);
    execFileSync(join(scripts, 'github-release.sh'), args, {
      env: { PATH: `${dir}:${process.env.PATH}`, GITHUB_REPOSITORY: 'o/r', FAKE_LOG: log, FAKE_RELEASE_EXISTS: exists ? 'yes' : 'no' },
    });
    return readFileSync(log, 'utf8').trim().split('\n');
  }

  it('creates the release as a draft, without making the tag', () => {
    const calls = run(['draft', '1.2.3', 'a.zip', 'a.zip.sha256'], false);
    expect(calls.at(-1)).toBe('release create v1.2.3 a.zip a.zip.sha256 --draft --verify-tag --title v1.2.3 --generate-notes --repo o/r');
    expect(calls.join('\n')).not.toContain('--draft=false');
  });

  it('replaces the files of a release that is already there and leaves its state alone', () => {
    const calls = run(['draft', '1.2.3', 'a.zip'], true);
    expect(calls.at(-1)).toBe('release upload v1.2.3 a.zip --clobber --repo o/r');
    expect(calls.join('\n')).not.toMatch(/release (create|edit)/);
  });

  it('attaches the appcast over an old one and publishes last', () => {
    expect(run(['attach', '1.2.3', 'appcast.xml'], true)).toEqual(['release upload v1.2.3 appcast.xml --clobber --repo o/r']);
    expect(run(['publish', '1.2.3'], true)).toEqual(['release edit v1.2.3 --draft=false --repo o/r']);
  });
});

describe('cask.mjs', () => {
  function ensure(text: string) {
    const file = join(mkdtempSync(join(tmpdir(), 'cask-')), 'carrier.rb');
    writeFileSync(file, text);
    execFileSync(join(scripts, 'cask.mjs'), ['ensure', file]);
    return readFileSync(file, 'utf8');
  }
  const once = (text: string, part: string) => text.split(part).length - 1;
  const old = `cask "carrier" do
  version "1.0.0"
  homepage "https://example.com"

  depends_on macos: :tahoe

  app "Carrier.app"

  postflight_steps do
    run "/usr/bin/xattr"
  end

  zap trash: "~/Library/Preferences/dev.ashulab.carrier.plist"
end
`;

  it('adds auto_updates and the cache to a cask that has neither, keeping the rest', () => {
    const out = ensure(old);
    expect(out).toContain('  auto_updates true\n  depends_on macos: :tahoe');
    expect(out).toContain('postflight_steps do\n    run "/usr/bin/xattr"\n  end');
    expect(out).toContain('  zap trash: [\n    "~/Library/Caches/dev.ashulab.carrier",\n    "~/Library/Preferences/dev.ashulab.carrier.plist",\n  ]\nend\n');
  });

  it('adds a zap to a cask that has none', () => {
    const out = ensure(old.replace(/ {2}zap trash.*\n/, ''));
    expect(out).toContain('  zap trash: [\n    "~/Library/Caches/dev.ashulab.carrier",\n  ]\nend\n');
  });

  it('declares each once however often it runs and changes nothing already right', () => {
    const first = ensure(old);
    const second = ensure(first);
    expect(second).toBe(first);
    expect(once(second, 'auto_updates')).toBe(1);
    expect(once(second, 'Library/Caches/dev.ashulab.carrier')).toBe(1);
    expect(ensure(readFileSync(seed, 'utf8'))).toBe(readFileSync(seed, 'utf8'));
  });

  it('turns auto_updates false into true', () => {
    expect(ensure(old.replace('  depends_on', '  auto_updates false\n  depends_on'))).toContain('  auto_updates true\n');
  });

  it('keeps the quarantine postflight of the seed', () => {
    expect(readFileSync(seed, 'utf8')).toContain('run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Carrier.app"]');
  });
});
