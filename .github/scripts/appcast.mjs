#!/usr/bin/env node
// The release's appcast, written and checked (docs/specs/carrier-updates-itself.md, "The release"). Node only, plus macOS's plutil and xmllint.
//   write <app> <zip> <signature> <out>   the one-item appcast for the zip, versions read from the app that was zipped
//   check <appcast> <app> <zip>           fails unless the appcast agrees with the app inside the zip and with the key
// `check` reads the private key from SPARKLE_PRIVATE_KEY (base64 of the 32-byte seed, what `sign_update --ed-key-file` takes). It is never printed.
import { execFileSync } from 'node:child_process';
import { createPrivateKey, createPublicKey, verify } from 'node:crypto';
import { readFileSync, statSync, writeFileSync } from 'node:fs';

const REPO = 'AshuLab/carrier';
const ARCH = 'arm64';
const PKCS8_ED25519_SEED = Buffer.from('302e020100300506032b657004220420', 'hex');

const fail = (message) => {
  console.error(`appcast: ${message}`);
  process.exit(1);
};

function plist(app, key) {
  const info = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', `${app}/Contents/Info.plist`], { encoding: 'utf8' }));
  const value = info[key];
  if (typeof value !== 'string' || value === '') fail(`${app} has no ${key} in its plist`);
  return value;
}

function write([app, zip, signature, out]) {
  const short = plist(app, 'CFBundleShortVersionString');
  const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Carrier</title>
    <item>
      <title>${short}</title>
      <sparkle:version>${plist(app, 'CFBundleVersion')}</sparkle:version>
      <sparkle:shortVersionString>${short}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${plist(app, 'LSMinimumSystemVersion')}</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>${ARCH}</sparkle:hardwareRequirements>
      <enclosure url="https://github.com/${REPO}/releases/download/v${short}/Carrier-${short}.zip" length="${statSync(zip).size}" type="application/octet-stream" sparkle:edSignature="${signature}"/>
    </item>
  </channel>
</rss>
`;
  writeFileSync(out, xml);
}

function check([appcast, app, zip]) {
  const xmllint = (args) => {
    try {
      return execFileSync('xmllint', [...args, appcast], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (error) {
      return fail(`${appcast} does not parse: ${error.stderr}`);
    }
  };
  xmllint(['--noout']);
  const xpath = (expression) => xmllint(['--xpath', expression]).trim();
  const named = (name) => `string(//*[local-name()="item"]/*[local-name()="${name}"])`;
  const enclosure = (attribute) => `string(//*[local-name()="enclosure"]/@*[local-name()="${attribute}"])`;

  const items = xpath('count(//*[local-name()="item"])');
  if (items !== '1') fail(`the appcast has ${items} items, expected exactly 1`);

  const mismatches = [];
  const expect = (what, found, expected) => {
    if (found !== expected) mismatches.push(`${what} is '${found}', expected '${expected}'`);
  };
  const short = plist(app, 'CFBundleShortVersionString');
  expect('sparkle:version', xpath(named('version')), plist(app, 'CFBundleVersion'));
  expect('sparkle:shortVersionString', xpath(named('shortVersionString')), short);
  expect('sparkle:minimumSystemVersion', xpath(named('minimumSystemVersion')), plist(app, 'LSMinimumSystemVersion'));
  expect('sparkle:hardwareRequirements', xpath(named('hardwareRequirements')), ARCH);
  expect('enclosure url', xpath(enclosure('url')), `https://github.com/${REPO}/releases/download/v${short}/Carrier-${short}.zip`);
  expect('enclosure length', xpath(enclosure('length')), String(statSync(zip).size));

  const secret = (process.env.SPARKLE_PRIVATE_KEY ?? '').trim();
  if (secret === '') fail('SPARKLE_PRIVATE_KEY is not set');
  const seed = Buffer.from(secret, 'base64');
  if (seed.length !== 32) fail('SPARKLE_PRIVATE_KEY is not the base64 of a 32-byte seed');
  const publicKey = createPublicKey(createPrivateKey({ key: Buffer.concat([PKCS8_ED25519_SEED, seed]), format: 'der', type: 'pkcs8' }));
  const derived = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
  expect('the public key derived from SPARKLE_PRIVATE_KEY', derived, plist(app, 'SUPublicEDKey'));

  const signature = Buffer.from(xpath(enclosure('edSignature')), 'base64');
  if (!verify(null, readFileSync(zip), publicKey, signature)) mismatches.push('the enclosure signature does not verify for the zip with the derived public key');

  if (mismatches.length > 0) fail(mismatches.join('\n'));
  console.log(`appcast ok: ${short}, build ${plist(app, 'CFBundleVersion')}, public key ${derived}`);
}

const [command, ...args] = process.argv.slice(2);
if (command === 'write' && args.length === 4) write(args);
else if (command === 'check' && args.length === 3) check(args);
else fail('usage: appcast.mjs write <app> <zip> <signature> <out> | check <appcast> <app> <zip>');
