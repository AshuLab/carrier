import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test } from 'vitest';
import { ChatRefused, textCode } from './runner.ts';

// The golden list of the codes a ChatRefused can carry ([ADR 0055](../../docs/adr/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)):
// every code with an example of its parameters, read by the app's tests. UPDATE_FIXTURES=1 rewrites it from the sources.
// A code is found where `new ChatRefused('<code>'` passes it, or where a helper's reason has `code: '<code>'` (`refusedFor` throws it).
const root = fileURLToPath(new URL('../', import.meta.url));
const file = fileURLToPath(new URL('../../macos/Tests/Fixtures/text-codes.json', import.meta.url));

function sources(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return sources(path);
    return entry.name.endsWith('.ts') && entry.name.endsWith('.test.ts') === false ? [path] : [];
  });
}

/** The index after the string, template or comment that starts at `at`, or `at` when none does. */
function skip(text: string, at: number): number {
  const c = text[at];
  if (c === '/' && text[at + 1] === '/') return text.indexOf('\n', at) === -1 ? text.length : text.indexOf('\n', at);
  if (c === '/' && text[at + 1] === '*') return text.indexOf('*/', at) + 2;
  if (c === "'" || c === '"') {
    let i = at + 1;
    while (text[i] !== c) i += text[i] === '\\' ? 2 : 1;
    return i + 1;
  }
  if (c === '`') {
    let i = at + 1;
    while (text[i] !== '`') {
      if (text[i] === '\\') i += 2;
      else if (text[i] === '$' && text[i + 1] === '{') i = close(text, i + 1) + 1;
      else i++;
    }
    return i + 1;
  }
  return at;
}

/** The index of the bracket that closes the one at `open`. */
function close(text: string, open: number): number {
  let depth = 0;
  for (let i = open; i < text.length; ) {
    const next = skip(text, i);
    if (next !== i) {
      i = next;
      continue;
    }
    if ('({['.includes(text[i]!)) depth++;
    if (')}]'.includes(text[i]!)) depth--;
    if (depth === 0) return i;
    i++;
  }
  throw new Error('unbalanced');
}

/** The top-level argument or property texts of what lies between the brackets that open at `open`. */
function parts(text: string, open: number): string[] {
  const end = close(text, open);
  const out: string[] = [];
  let from = open + 1;
  for (let i = open + 1; i < end; ) {
    const next = skip(text, i);
    if (next !== i) {
      i = next;
      continue;
    }
    if ('({['.includes(text[i]!)) i = close(text, i);
    else if (text[i] === ',') {
      out.push(text.slice(from, i).trim());
      from = i + 1;
    }
    i++;
  }
  const last = text.slice(from, end).trim();
  return last === '' ? out : [...out, last];
}

/** The keys of the object literal `{ a, b: 1 }`, or null when the text is not one. */
const keysOf = (object: string): string[] | null => (object.startsWith('{') === false ? null : parts(object, 0).map((entry) => /^[a-zA-Z]+/.exec(entry)![0]));

type Found = { code: string; keys: string[] | null; at: string };

function found(): Found[] {
  const out: Found[] = [];
  for (const path of sources(root)) {
    const text = readFileSync(path, 'utf8');
    const at = path.slice(root.length);
    for (const call of text.matchAll(/new ChatRefused\(/g)) {
      const open = call.index + call[0].length - 1;
      const args = parts(text, open);
      // a code is a literal, or a choice between literals
      const codes = [...args[0]!.matchAll(/'([^']+)'/g)].map((literal) => literal[1]!);
      // a code that is handed on (`refusedFor`, a refusal caught and thrown again with more words) was found where it began
      if (codes.length === 0) expect(`${at}: ${args[0]}`, 'a ChatRefused takes its code as a string literal').toMatch(/: (reason|error)\.code$/);
      for (const code of codes) out.push({ code, keys: args[2] === undefined ? [] : keysOf(args[2]), at });
    }
    if (at.startsWith('chat/') === false && at.startsWith('usage/') === false) continue;
    for (const reason of text.matchAll(/\bcode: '([^']+)'/g)) {
      // the object literal that holds it, to read its `params`
      let open = reason.index;
      while (text[open] !== '{' || close(text, open) < reason.index) open--;
      const params = parts(text, open).find((entry) => entry.startsWith('params:'));
      out.push({ code: reason[1]!, keys: params === undefined ? [] : keysOf(params.slice('params:'.length).trim()), at });
    }
  }
  return out;
}

type Golden = Record<string, { params: Record<string, string | number> }>;

test('macos/Tests/Fixtures/text-codes.json lists every code a ChatRefused can carry, with an example of its parameters', () => {
  const all = found();
  expect(all.length).toBeGreaterThan(100);
  const keysByCode = new Map<string, string[]>();
  for (const { code, keys, at } of all) {
    expect(code, `${at}: ${code} is not a text code`).toMatch(textCode);
    const sorted = [...(keys ?? [])].sort();
    const seen = keysByCode.get(code);
    // a code with two shapes of parameters could not be given one example, nor one sentence by a front-end
    if (seen !== undefined) expect(sorted, `${at}: ${code} has other parameters elsewhere`).toEqual(seen);
    else keysByCode.set(code, sorted);
  }
  const previous: Golden = process.env.UPDATE_FIXTURES === '1' ? JSON.parse(readFileSync(file, 'utf8')) : {};
  if (process.env.UPDATE_FIXTURES === '1') {
    const golden: Golden = {};
    for (const code of [...keysByCode.keys()].sort()) {
      const kept = previous[code]?.params ?? {};
      golden[code] = { params: Object.fromEntries(keysByCode.get(code)!.map((key) => [key, kept[key] ?? 'example'])) };
    }
    writeFileSync(file, `${JSON.stringify(golden, null, 2)}\n`);
  }
  const golden = JSON.parse(readFileSync(file, 'utf8')) as Golden;
  expect(Object.keys(golden).sort(), 'a code in src/ is missing from the list, or the list has one no source throws; UPDATE_FIXTURES=1 pnpm test rewrites it').toEqual([...keysByCode.keys()].sort());
  for (const [code, { params }] of Object.entries(golden)) {
    expect(code).toMatch(textCode);
    expect(Object.keys(params).sort(), `${code}: the example has other parameters than the source`).toEqual(keysByCode.get(code));
    for (const value of Object.values(params)) expect(['string', 'number']).toContain(typeof value);
  }
});

test('a code that is not a text code, or a parameter that is not a string or a number, does not pass the checks of the list', () => {
  for (const bad of ['Session.busy', 'busy', 'session.', 'session..busy', 'session.Busy', 'session.busy2', 'session busy', '']) expect(bad).not.toMatch(textCode);
  for (const good of ['session.busy', 'session.option.unknown', 'worktree.nameTaken']) expect(good).toMatch(textCode);
  // the constructor keeps what it is given, so the tests above are what refuses a bad one
  const refused = new ChatRefused('session.busy', 'This session is working', { count: 2 });
  expect([refused.code, refused.message, refused.params]).toEqual(['session.busy', 'This session is working', { count: 2 }]);
});
