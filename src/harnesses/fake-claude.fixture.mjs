#!/usr/bin/env node
// Stand-in for the claude binary in host-runner.integration.test.ts: the --model value picks the behavior.
// Lines have the shape claude 2.1.301 prints.
import { spawn } from 'node:child_process';
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
} else if (mode === 'usage_limit') {
  // The real 429 result of epic #302's failed executions, then the exit the claude CLI makes on an error result.
  console.log(readFileSync(new URL('./claude-usage-limit.fixture.jsonl', import.meta.url), 'utf8').trimEnd());
  process.exit(1);
} else if (mode === 'usage_limit_exit0') {
  // The same 429 result, but the process ends 0 (a wrapper, or a CLI that recovers its exit code).
  console.log(readFileSync(new URL('./claude-usage-limit.fixture.jsonl', import.meta.url), 'utf8').trimEnd());
  process.exit(0);
} else if (mode === 'child' || mode === 'child-escaped' || mode === 'child-term') {
  // A child that ignores SIGTERM and keeps this process's stdout open. 'child-escaped' leaves the process group.
  const child = spawn(process.execPath, ['-e', "process.on('SIGTERM', () => {}); setInterval(() => {}, 1000)"], {
    stdio: ['ignore', 'inherit', 'inherit'],
    detached: mode === 'child-escaped',
  });
  writeFileSync(join(process.cwd(), 'child.pid'), String(child.pid));
  child.unref();
  if (mode === 'child-term') {
    // The leader exits on SIGTERM and leaves the child behind.
    process.on('SIGTERM', () => process.exit(0));
    setInterval(() => {}, 1000);
  } else process.exit(0);
} else if (mode === 'chatty') {
  // Writes every 200 ms for a second, then ends: never silent long enough for a short idle limit.
  let n = 0;
  const timer = setInterval(() => {
    out({ type: 'assistant', message: { content: [{ type: 'text', text: `tick ${++n}` }] } });
    if (n === 5) process.exit(0);
  }, 200);
  void timer;
} else if (mode === 'hang') {
  setInterval(() => {}, 1000);
} else {
  process.exit(mode === 'fail' ? 3 : 0);
}
