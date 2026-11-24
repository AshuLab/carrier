#!/usr/bin/env node
// The cask the release pushes to the tap, made to declare what the app needs (docs/specs/carrier-updates-itself.md, "The release").
//   ensure <cask.rb>   adds `auto_updates true` and Sparkle's cache folder to `zap`, once each, whether or not the file had them
//   release <cask.rb> <version> <arm64-sha256> <intel-sha256>   the version and, for each architecture, its zip and checksum (`on_arm` and `on_intel`), and no `depends_on arch:`;
//                      it also turns the flat cask of the first releases (one url, one sha256, Apple Silicon only) into that shape
// The tap's cask is rewritten from the tap's own copy, so this runs on that copy as well as on the seed in this repo. Node only.
import { readFileSync, writeFileSync } from 'node:fs';

const REPO = 'AshuLab/carrier';
const BUNDLE_ID = 'dev.ashulab.carrier';
const CACHE = `~/Library/Caches/${BUNDLE_ID}`;

const fail = (message) => {
  console.error(`cask: ${message}`);
  process.exit(1);
};

function ensureAutoUpdates(lines) {
  const at = lines.findIndex((line) => /^ {2}auto_updates\b/.test(line));
  if (at >= 0) {
    lines[at] = '  auto_updates true';
    return;
  }
  // Homebrew's stanza order: auto_updates comes after homepage and before depends_on.
  const before = lines.findIndex((line) => /^ {2}(depends_on|conflicts_with|app|pkg|binary)\b/.test(line));
  if (before < 0) fail('the cask has no depends_on or app stanza to put auto_updates before');
  lines.splice(before, 0, '  auto_updates true');
}

function ensureZapCache(lines) {
  const start = lines.findIndex((line) => /^ {2}zap\b/.test(line));
  if (start < 0) {
    const end = lines.lastIndexOf('end');
    if (end < 0) fail('the cask has no closing end');
    lines.splice(end, 0, '', ...zap([CACHE]));
    return;
  }
  let stop = start;
  if (/\[\s*$/.test(lines[start])) {
    stop = lines.findIndex((line, i) => i > start && /^\s*\]\s*$/.test(line));
    if (stop < 0) fail('the zap list is not closed');
  }
  const stanza = lines.slice(start, stop + 1).join('\n');
  if (!/^ {2}zap\s+trash:/.test(stanza)) fail('zap has something other than trash: the script does not rewrite it');
  const paths = [...stanza.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  if (paths.includes(CACHE)) return;
  lines.splice(start, stop - start + 1, ...zap([...paths, CACHE]));
}

// Homebrew's style wants the list sorted and with a trailing comma.
const zap = (paths) => ['  zap trash: [', ...paths.toSorted().map((path) => `    "${path}",`), '  ]'];

// The Intel app is its own zip (`Carrier-<version>-intel.zip`), as appcast.mjs names it. Rewritten whole each time, so a run never adds to the last one.
function setRelease(lines, version, arm, intel) {
  if (!/^\d+\.\d+\.\d+$/.test(version)) fail(`'${version}' is not X.Y.Z`);
  for (const sha of [arm, intel]) if (!/^[0-9a-f]{64}$/.test(sha)) fail(`'${sha}' is not a sha256`);
  const keep = [];
  for (let i = 0; i < lines.length; i++) {
    if (/^ {2}on_(arm|intel) do$/.test(lines[i])) {
      i = lines.indexOf('  end', i);
      if (i < 0) fail('an on_arm or on_intel block is not closed');
    } else if (/^ {2}url\b.*,\s*$/.test(lines[i])) {
      fail('the cask has a url with options: the script does not rewrite it');
    } else if (!/^ {2}(sha256|url|depends_on arch:)/.test(lines[i])) {
      keep.push(lines[i]);
    }
  }
  const at = keep.findIndex((line) => /^ {2}version\b/.test(line));
  if (at < 0) fail('the cask has no version stanza');
  keep[at] = `  version "${version}"`;
  while (keep[at + 1] === '') keep.splice(at + 1, 1);
  const url = (suffix) => `    url "https://github.com/${REPO}/releases/download/v#{version}/Carrier-#{version}${suffix}.zip"`;
  keep.splice(at + 1, 0, '', '  on_arm do', `    sha256 "${arm}"`, url(''), '  end', '  on_intel do', `    sha256 "${intel}"`, url('-intel'), '  end', '');
  lines.splice(0, lines.length, ...keep);
}

const [command, file, ...rest] = process.argv.slice(2);
if (!file || !(command === 'ensure' && rest.length === 0) && !(command === 'release' && rest.length === 3)) {
  fail('usage: cask.mjs ensure <cask.rb> | release <cask.rb> <version> <arm64-sha256> <intel-sha256>');
}
const lines = readFileSync(file, 'utf8').split('\n');
if (command === 'release') setRelease(lines, ...rest);
else {
  ensureAutoUpdates(lines);
  ensureZapCache(lines);
}
writeFileSync(file, lines.join('\n'));
