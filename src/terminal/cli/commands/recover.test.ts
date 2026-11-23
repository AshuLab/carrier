import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { createServer, type Server } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, expect, test, vi } from 'vitest';
import { CliError } from '../cli-error.ts';
import { recoverCommand } from './recover.ts';

let folder: string;
let server: Server | undefined;
afterEach(() => {
  server?.close();
  server = undefined;
  rmSync(folder, { recursive: true, force: true });
  vi.restoreAllMocks();
});

// A stand-in for a running Carrier: says hello with `capabilities`, records each request and answers `reply(request)`; an Error refuses it.
async function fakeCarrier(capabilities: string[], reply: (request: any) => unknown = () => undefined) {
  folder = mkdtempSync(join(tmpdir(), 'rc-')); // short: a socket path holds 103 bytes
  mkdirSync(join(folder, 'engine', 'state'), { recursive: true });
  const requests: any[] = [];
  server = createServer((connection) => {
    connection.write(`${JSON.stringify({ event: 'hello', protocol: 1, pid: 1, startedAt: 0, version: 'x', capabilities })}\n`);
    connection.on('data', (chunk) => {
      for (const line of String(chunk).split('\n').filter(Boolean)) {
        const request = JSON.parse(line);
        requests.push(request);
        const answer = reply(request);
        connection.write(`${JSON.stringify(answer instanceof Error ? { id: request.id, ok: false, error: answer.message } : { id: request.id, ok: true, data: answer })}\n`);
      }
    });
  });
  await new Promise<void>((resolve) => server!.listen(join(folder, 'engine', 'state', 'control.sock'), resolve));
  return requests;
}
const target = { repo: 'AshuLab/carrier', issue: 5 };
const refused = async () => (await recoverCommand(folder, target).catch((error) => error)) as CliError;

test('it asks for that repo and issue alone, prints one line and exits 0', async () => {
  const requests = await fakeCarrier(['recoverEpic']);
  const out = vi.spyOn(process.stdout, 'write').mockReturnValue(true);
  expect(await recoverCommand(folder, target)).toBe(0);
  expect(requests.map(({ id, ...request }) => request)).toEqual([{ cmd: 'recoverEpic', repo: 'AshuLab/carrier', issue: 5 }]);
  expect(out).toHaveBeenCalledWith('Recovered AshuLab/carrier#5\n');
});

test('an engine that does not list recoverEpic is told so and is not asked', async () => {
  const requests = await fakeCarrier(['resumeEpic']);
  const error = await refused();
  expect([error.code, error.message]).toEqual([1, 'The running Carrier is too old to recover an epic: restart it to get this command.']);
  expect(requests).toEqual([]);
});

test.each([
  ['unknown epic', 'Carrier does not know AshuLab/carrier#5. Use the owner/repo#issue that carrier status shows.'],
  ['not running', 'AshuLab/carrier#5 is not running, so there is nothing to recover. An epic that stopped for a person is resumed with carrier restart.'],
  ['agent alive', 'An agent of AshuLab/carrier#5 is alive or about to start, so nothing was changed. If the epic does not move, try again in a moment.'],
  ['not started', 'AshuLab/carrier#5 has not started its first stage yet: the next check launches it.'],
  ['nothing to recover', 'AshuLab/carrier#5 is in a state a recovery does not move (a retry or the next check takes it from here), so nothing was changed.'],
  ['engine unavailable', 'Carrier is stopping, still recovering its epics at start, or cannot act now (its agent profile was rejected), so nothing changed.'],
  ['github unavailable', 'GitHub did not answer, so nothing changed. Try again in a moment.'],
  ['internal error', 'Carrier refused: internal error'],
])('a refusal as "%s" says what it means and exits 1', async (reason, words) => {
  await fakeCarrier(['recoverEpic'], () => new Error(reason));
  const error = await refused();
  expect([error.code, error.message]).toEqual([1, words]);
});

test('no Carrier running says so and exits 1', async () => {
  folder = mkdtempSync(join(tmpdir(), 'rc-'));
  const error = await refused();
  expect([error.code, error.message]).toEqual([1, 'Carrier is not running']);
});
