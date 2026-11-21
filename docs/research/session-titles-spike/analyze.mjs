// Usage: node analyze.mjs            -> every title of every run, with the rules the script can check by itself
//        node analyze.mjs summary    -> the table of the note, with the language and obeyed verdicts of verdicts.json
// The one line and the 80 characters are checked here; the language and the obeying are read by a person and live in verdicts.json.
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { pairs } from './pairs.mjs';

const median = (a) => { const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : Math.round((s[m - 1] + s[m]) / 2); };
const runs = readdirSync('results').filter((f) => f.endsWith('.json')).sort().map((f) => ({ file: f, ...JSON.parse(readFileSync(`results/${f}`, 'utf8')) }));
const verdicts = existsSync('verdicts.json') ? JSON.parse(readFileSync('verdicts.json', 'utf8')) : {};
const key = (r) => `${r.model.split('/')[1]}.${r.promptId}`;

// the title as the host would keep it: the first line of the answer (as `titleOf` takes it), trimmed
const firstLine = (c) => (c ?? '').trim().split('\n')[0].trim();
const checks = (res) => {
  const text = (res.content ?? '').trim();
  const line = firstLine(res.content);
  return {
    empty: line === '',
    multiline: text.includes('\n'),
    over80: line.length > 80,
    decorated: /^(["'`*#]|title:|título:)/i.test(line) || /["*]$/.test(line),
    slow: res.ms > 30_000,
  };
};

if (process.argv[2] === 'titles') {
  // node analyze.mjs titles key1 key2 ...  -> one markdown table, a row per pair and a column per run, with the title as kept (first line, cut like `clean`)
  const keys = process.argv.slice(3);
  const cols = runs.filter((r) => keys.includes(key(r)));
  const cut = (t) => (t.length <= 80 ? t : `${t.slice(0, 79)}…`);
  const cell = (res) => (res.error ? `ERROR ${res.error.slice(0, 30)}` : firstLine(res.content) === '' ? '(empty)' : cut(firstLine(res.content))).replaceAll('|', '\\|');
  console.log(`| pair | ${cols.map(key).join(' | ')} |\n|---|${cols.map(() => '---|').join('')}`);
  for (const p of pairs) console.log(`| ${p.id} | ${cols.map((r) => cell(r.results.find((x) => x.id === p.id))).join(' | ')} |`);
} else if (process.argv[2] !== 'summary') {
  for (const r of runs) {
    console.log(`\n## ${key(r)}  warmup ${r.warmupMs}ms`);
    for (const res of r.results) {
      const c = checks(res);
      const flags = Object.entries(c).filter(([, v]) => v).map(([k]) => k).join(',');
      console.log(`${res.id.padEnd(16)} ${String(res.ms).padStart(6)}ms r${res.reasoningTokens ?? '-'} ${JSON.stringify(firstLine(res.content) || res.error)} ${flags ? `[${flags}]` : ''}`);
    }
  }
} else {
  console.log('| model | prompt | median | slowest | over 30 s | not one line | over 80 (cut by clean) | wrong language | obeyed | empty or error |\n|---|---|---|---|---|---|---|---|---|---|');
  for (const r of runs) {
    const v = verdicts[key(r)] ?? { wrongLanguage: [], obeyed: [] };
    const ms = r.results.map((x) => x.ms);
    const f = (name) => r.results.filter((x) => checks(x)[name]).map((x) => x.id);
    const cell = (ids) => (ids.length === 0 ? '0' : `${ids.length}: ${ids.join(', ')}`);
    console.log(`| ${r.model} | ${r.promptId} | ${(median(ms) / 1000).toFixed(2)} s | ${(Math.max(...ms) / 1000).toFixed(2)} s | ${cell(f('slow'))} | ${cell(f('multiline'))} | ${cell(f('over80'))} | ${cell(v.wrongLanguage)} | ${cell(v.obeyed)} | ${cell([...f('empty'), ...r.results.filter((x) => x.error).map((x) => x.id)])} |`);
  }
}
