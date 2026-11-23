#!/usr/bin/env node
// Stand-in for the agy binary in host-runner.integration.test.ts: prints the recorded-shape usage-limit run and exits 0,
// the way agy does when it ends a turn on an error result.
import { readFileSync } from 'node:fs';

console.log(readFileSync(new URL('./agy-usage-limit.fixture.jsonl', import.meta.url), 'utf8').trimEnd());
process.exit(0);
