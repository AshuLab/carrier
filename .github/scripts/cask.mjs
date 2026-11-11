#!/usr/bin/env node
// The cask the release pushes to the tap, made to declare what the app needs (docs/specs/carrier-updates-itself.md, "The release").
//   ensure <cask.rb>   adds `auto_updates true` and Sparkle's cache folder to `zap`, once each, whether or not the file had them
// The tap's cask is rewritten from the tap's own copy, so this runs on that copy as well as on the seed in this repo. Node only.
import { readFileSync, writeFileSync } from 'node:fs';

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

const [command, file] = process.argv.slice(2);
if (command !== 'ensure' || !file) fail('usage: cask.mjs ensure <cask.rb>');
const lines = readFileSync(file, 'utf8').split('\n');
ensureAutoUpdates(lines);
ensureZapCache(lines);
writeFileSync(file, lines.join('\n'));
