// Child process for lock.test.ts: takes the lock, reports, and holds it until stdin closes.
import { acquireLock } from './lock.ts';

const lock = acquireLock(process.argv[2] ?? '');
console.log(lock.ok ? 'locked' : 'busy');
if (lock.ok) {
  process.stdin.resume();
  process.stdin.on('end', () => {
    lock.release();
  });
} else {
  process.exit(1);
}
