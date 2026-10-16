// Child process for logger.test.ts: a real process with file logging installed. It logs, prints 'ready'
// on stdout (the only thing the terminal may get) and keeps logging until the test sends SIGINT.
import { createScopedLogger, LogLevel } from '@ashulab/universal-logger';
import { installFileLogging } from './logger.ts';

installFileLogging(process.argv[2]!, LogLevel.INFO);
const log = createScopedLogger('fixture');

log.info('token ghp_abcdefghijklmnopqrstuvwxyz0123456789 here', { repo: 'a/b', epic: 7, note: 'ghs_Zz9Zz9Zz9 and github_pat_11AAA_bbb' });
log.debug('hidden');
log.error('failed', new Error('boom'), { executionId: 'e1', stage: 'fix', round: 2 });
console.error('from a dependency');
let seq = 0;
for (; seq < 50; seq++) log.info('tick', { seq: seq + 1 });
process.stdout.write('ready\n');
setInterval(() => log.info('tick', { seq: ++seq }), 2);
