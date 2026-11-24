import { mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createServer, type Server } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, expect, test, vi } from 'vitest';
import { CliError } from '../cli-error.ts';
import { recoverCommand, refusals } from './recover.ts';

let folder: string;
let server: Server | undefined;
afterEach(() => {
  server?.close();
  server = undefined;
  rmSync(folder, { recursive: true, force: true });
  vi.restoreAllMocks();
});

// A refusal as the engine words it: `words` are not the engine's today, so a table keyed by them would miss; `code` is absent for an engine that predates the codes.
const refusal = (words: string, code?: string) => Object.assign(new Error(words), { code });
const code = (error: Error) => (error as Error & { code?: string }).code;

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
        connection.write(`${JSON.stringify(answer instanceof Error ? { id: request.id, ok: false, error: answer.message, ...(code(answer) && { code: code(answer), params: {} }) } : { id: request.id, ok: true, data: answer })}\n`);
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
  ['epic.unknown', 'Carrier does not know AshuLab/carrier#5. Use the owner/repo#issue that carrier status shows.'],
  ['recover.notRunning', 'AshuLab/carrier#5 is not running, so there is nothing to recover. An epic that stopped for a person is resumed with carrier restart.'],
  ['recover.agentAlive', 'An agent of AshuLab/carrier#5 is alive or about to start, so nothing was changed. If the epic does not move, try again in a moment.'],
  ['recover.notStarted', 'AshuLab/carrier#5 has not started its first stage yet: the next check launches it.'],
  ['recover.nothingToRecover', 'AshuLab/carrier#5 is in a state a recovery does not move (a retry or the next check takes it from here), so nothing was changed.'],
  ['recover.engineUnavailable', 'Carrier is stopping, still recovering its epics at start, or cannot act now (its agent profile was rejected), so nothing changed.'],
  ['github.unavailable', 'GitHub did not answer, so nothing changed. Try again in a moment.'],
  ['request.internal', 'Carrier refused: refused in other words'],
])('a refusal with the code %s, in whatever words, says what it means and exits 1', async (reason, words) => {
  await fakeCarrier(['recoverEpic'], () => refusal('refused in other words', reason));
  const error = await refused();
  expect([error.code, error.message]).toEqual([1, words]);
});

test('a refusal without a code is printed with its words', async () => {
  await fakeCarrier(['recoverEpic'], () => refusal('not running'));
  const error = await refused();
  expect([error.code, error.message]).toEqual([1, 'Carrier refused: not running']);
});

test('every code the table is keyed by is in the golden list of text codes', () => {
  const codes = Object.keys(JSON.parse(readFileSync(fileURLToPath(new URL('../../../../macos/Tests/Fixtures/text-codes.json', import.meta.url)), 'utf8')));
  expect(Object.keys(refusals).filter((code) => codes.includes(code) === false)).toEqual([]);
});

test('no Carrier running says so and exits 1', async () => {
  folder = mkdtempSync(join(tmpdir(), 'rc-'));
  const error = await refused();
  expect([error.code, error.message]).toEqual([1, 'Carrier is not running']);
});
