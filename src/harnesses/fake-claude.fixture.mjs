#!/usr/bin/env node
// Stand-in for the claude binary in host-runner.integration.test.ts: the --model value picks the behavior.
// Lines have the shape claude 2.1.301 prints.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const args = process.argv.slice(2);
const mode = args[args.indexOf('--model') + 1];
const out = (event) => console.log(JSON.stringify(event));
out({ type: 'system', subtype: 'init', cwd: process.cwd(), session_id: `session-${process.pid}` });

if (mode === 'auth') {
  out({ type: 'assistant', error: 'authentication_failed', message: { content: [{ type: 'text', text: 'Not logged in · Please run /login' }] } });
  out({ type: 'result', is_error: true, api_error_status: null, result: 'Not logged in · Please run /login' });
  process.exit(1);
} else if (mode === 'env') {
  // The test reads what this process was given; the token itself is never printed.
  const { GH_TOKEN, GITHUB_TOKEN, GIT_AUTHOR_NAME } = process.env;
  writeFileSync(join(process.cwd(), 'env.json'), JSON.stringify({ GH_TOKEN, GITHUB_TOKEN, GIT_AUTHOR_NAME, args }));
  setTimeout(() => process.exit(0), 500);
} else if (mode === 'stream') {
  // A recorded-shape run: the lines of claude-events.fixture.jsonl, one write per line.
  const fixture = new URL('./claude-events.fixture.jsonl', import.meta.url);
  for (const line of readFileSync(fixture, 'utf8').trimEnd().split('\n')) console.log(line);
  process.exit(0);
} else if (mode === 'kill') {
  // Ends the way the real 137s did: a SIGKILL nobody in the run sent.
  process.kill(process.pid, 'SIGKILL');
} else if (mode === 'token') {
  // A final output that holds a token at character 290, where a plain cut at 300 would split it.
  out({ type: 'result', is_error: true, api_error_status: null, result: `${'x '.repeat(145)}ghp_${'a'.repeat(36)} done` });
  process.exit(3);
} else if (mode === 'hang') {
  setInterval(() => {}, 1000);
} else {
  process.exit(mode === 'fail' ? 3 : 0);
}
