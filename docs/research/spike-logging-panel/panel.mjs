// Throwaway spike (issue #9). Not product code. See ../logging-panel.md
// Usage: node panel.mjs --log=<file> --redirect=yes|no --sigint=handler|default --count-file=<file>
import { closeSync, openSync, writeSync } from 'node:fs';
import { format } from 'node:util';
import {
  LogLevel, configureUniversalLogger, createScopedLogger, logDebug, logError, logInfo, logWarn,
} from '@ashulab/universal-logger';

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3) ?? d;
const logFile = arg('log', 'spike.log');
const redirect = arg('redirect', 'yes') === 'yes';
const sigint = arg('sigint', 'handler');
const countFile = arg('count-file', '');

// The library calls console.info/warn/error/log at call time, so replacing the methods is enough.
// Sync append on one fd: every call is in the kernel before it returns, so SIGINT/exit cannot lose it.
if (redirect) {
  const fd = openSync(logFile, 'a');
  for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
    console[level] = (...args) => writeSync(fd, `[${level}] ${format(...args)}\n`);
  }
}

configureUniversalLogger({ enabled: true, minLevel: LogLevel.INFO });

let emitted = 0; // each emit() writes exactly one INFO+ line; the debug line is below minLevel and must NOT appear
const scoped = createScopedLogger('spike');
const emit = () => {
  const n = ++emitted;
  logDebug(`DEBUGLINE seq=${n}`); // below minLevel: must not appear
  if (n % 5 === 0) logError(`LOGLINE seq=${n} error`, new Error(`kaboom-${n}`), { epic: 'x' });
  else if (n % 5 === 3) logWarn(`LOGLINE seq=${n} warn`, { epic: 'x' });
  else if (n % 5 === 4) scoped.warn(`LOGLINE seq=${n} scoped-warn-with-Error`, new Error(`scoped-${n}`));
  else logInfo(`LOGLINE seq=${n} info`, { epic: 'x' });
};

// Panel: redraw in place with ANSI. Never contains the log markers.
let drawn = 0;
const frame = () => {
  const lines = ['== carrier panel ==', `slots 1/3   tick ${drawn}`, `logs emitidos: ${emitted}`, '==================='];
  const up = drawn > 0 ? `\x1b[${lines.length}A` : '';
  drawn++;
  writeSync(1, up + lines.map((l) => `\x1b[2K${l}\n`).join(''));
};

const finish = (code) => {
  if (countFile) { const fd = openSync(countFile, 'w'); writeSync(fd, String(emitted)); closeSync(fd); }
  writeSync(1, '\x1b[?25h');
  process.exit(code);
};
if (sigint === 'handler') process.on('SIGINT', () => { logInfo('LOGLINE shutdown'); emitted++; finish(130); });

writeSync(1, '\x1b[?25l');
setInterval(emit, 37);
setInterval(frame, 50);
