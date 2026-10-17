#!/usr/bin/env node
// Stand-in for the codex binary in host-runner.integration.test.ts: the --model value picks the behavior.
// Lines have the shape codex 0.153.4 prints (`exec --json`); a lost session prints plain text on stderr.
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

const args = process.argv.slice(2);
const mode = args[args.indexOf('--model') + 1];
const out = (event) => console.log(JSON.stringify(event));

if (mode === 'lost') {
  console.error('Error: thread/resume: thread/resume failed: no rollout found for thread id x (code -32600)');
  process.exit(1);
}
out({ type: 'thread.started', thread_id: args[1] === 'resume' ? args[2] : `session-${process.pid}` });
out({ type: 'turn.started' });

if (mode === 'auth') {
  out({ type: 'error', message: 'Reconnecting... 2/5 (unexpected status 401 Unauthorized: Missing bearer or basic authentication in header)' });
  out({ type: 'turn.failed', error: { message: 'unexpected status 401 Unauthorized: Missing bearer or basic authentication in header' } });
  process.exit(1);
} else if (mode === 'retry') {
  // A 401 that is only a retry and then recovers is not a login failure.
  out({ type: 'error', message: 'Reconnecting... 1/5 (unexpected status 401 Unauthorized)' });
  out({ type: 'turn.completed' });
} else if (mode === 'env') {
  const { GH_TOKEN, GITHUB_TOKEN, GIT_AUTHOR_NAME } = process.env;
  writeFileSync(join(process.cwd(), 'env.json'), JSON.stringify({ GH_TOKEN, GITHUB_TOKEN, GIT_AUTHOR_NAME, args }));
  setTimeout(() => process.exit(0), 500);
} else if (mode === 'hang') {
  setInterval(() => {}, 1000);
} else {
  out({ type: 'turn.completed' });
  process.exit(mode === 'fail' ? 3 : 0);
}
