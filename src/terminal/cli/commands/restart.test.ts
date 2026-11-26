import { mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createServer, type Server } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, expect, test, vi } from 'vitest';
import type { Ui } from '../../prompts/types.ts';
import { CliError } from '../cli-error.ts';
import { askRestartOptions, refusals, restartCommand } from './restart.ts';

let folder: string | undefined;
let server: Server | undefined;
afterEach(() => {
  server?.close();
  server = undefined;
  if (folder) rmSync(folder, { recursive: true, force: true });
  vi.restoreAllMocks();
});

// A refusal as the engine words it: `words` are not the engine's today, so a table keyed by them would miss; `code` is absent for an engine that predates the codes.
const refusal = (words: string, code?: string) => Object.assign(new Error(words), { code });
const code = (error: Error) => (error as Error & { code?: string }).code;

// A stand-in for a running Carrier: says hello with `capabilities`, records each request and answers `reply(request)`; an Error refuses it.
async function fakeCarrier(capabilities: string[], reply: (request: any) => unknown = () => undefined) {
  folder = mkdtempSync(join(tmpdir(), 'rs-')); // short: a socket path holds 103 bytes
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
  await new Promise<void>((resolve) => server!.listen(join(folder!, 'engine', 'state', 'control.sock'), resolve));
  return requests;
}
const target = { repo: 'AshuLab/carrier', issue: 5 };
const sent = (requests: any[]) => requests.map(({ id, ...request }) => request);

const options = { names: ['claude', 'codex'], author: 'claude', reviewer: 'codex' };

// A terminal that records each question and answers it from `answers`, or with the preselected option.
function scripted(answers: Record<string, string> = {}) {
  const asked: { message: string; initialValue?: string; hints: Record<string, string | undefined> }[] = [];
  const ui = {
    select: async ({ message, options: choices, initialValue }) => {
      asked.push({ message, initialValue, hints: Object.fromEntries(choices.map((c) => [c.value, c.hint])) });
      return (answers[message] ?? initialValue) as never;
    },
  } satisfies Pick<Ui, 'select'>;
  return { ui, asked };
}

test('it asks for each role with its current option preselected and marks the author when the epic stopped in ship or fix', async () => {
  const { ui, asked } = scripted({ 'Option for the author': 'codex' });
  expect(await askRestartOptions({ stage: 'fix', options }, ui)).toEqual({ author: 'codex', reviewer: 'codex' });
  expect(asked).toEqual([
    { message: 'Option for the author', initialValue: 'claude', hints: { claude: 'current, failed', codex: undefined } },
    { message: 'Option for the reviewer', initialValue: 'codex', hints: { claude: undefined, codex: 'current' } },
  ]);
});

test('it marks the reviewer when the epic stopped in review', async () => {
  const { ui, asked } = scripted();
  expect(await askRestartOptions({ stage: 'review', options }, ui)).toEqual({ author: 'claude', reviewer: 'codex' });
  expect(asked.map((q) => q.hints)).toEqual([{ claude: 'current', codex: undefined }, { claude: undefined, codex: 'current, failed' }]);
});

test('the option that ran out is not preselected for the role that stopped the epic, and is marked', async () => {
  const { ui, asked } = scripted();
  expect(await askRestartOptions({ stage: 'ship', needsHumanKind: 'usage_limit', options }, ui)).toEqual({ author: 'codex', reviewer: 'codex' });
  expect(asked[0]).toEqual({ message: 'Option for the author', initialValue: 'codex', hints: { claude: 'ran out', codex: undefined } });
  expect(asked[1]!.initialValue).toBe('codex'); // the other role keeps its own
});

test('it asks nothing of an epic with a single option, none, or one Carrier does not list', async () => {
  const { ui, asked } = scripted();
  expect(await askRestartOptions({ stage: 'ship', options: { ...options, names: ['claude'] } }, ui)).toEqual({});
  expect(await askRestartOptions({ stage: 'ship', options: undefined }, ui)).toEqual({});
  expect(await askRestartOptions(undefined, ui)).toEqual({});
  expect(asked).toEqual([]);
});

const several = { ...options, extraReviewers: ['claude', 'codex'], lead: 'claude' };

// The extra reviewers are not asked about until `carrier restart` takes them by their key: the request names them by it and this command does not send it yet.
test('it asks for the lead the epic has beside the author and the reviewer, and not for the extra reviewers', async () => {
  const { ui, asked } = scripted({ 'Option for the reviewer': 'claude' });
  expect(await askRestartOptions({ stage: 'review', options: { ...several, failed: 'seguridad-api' } }, ui)).toEqual({ author: 'claude', reviewer: 'claude', lead: 'claude' });
  expect(asked.map((q) => [q.message, q.initialValue, q.hints])).toEqual([
    ['Option for the author', 'claude', { claude: 'current', codex: undefined }],
    ['Option for the reviewer', 'codex', { claude: undefined, codex: 'current' }],
    ['Option for the lead', 'claude', { claude: 'current', codex: undefined }],
  ]);
});

test('the lead is marked as failed, and the lead that ran out of usage is not preselected', async () => {
  const { ui, asked } = scripted();
  await askRestartOptions({ stage: 'review', needsHumanKind: 'usage_limit', options: { ...several, failed: 'lead' } }, ui);
  expect(asked.at(-1)).toEqual({ message: 'Option for the lead', initialValue: 'codex', hints: { claude: 'ran out', codex: undefined } });
});

test('an engine that does not take the extra roles is asked for the author and the reviewer only', async () => {
  const { ui, asked } = scripted();
  expect(await askRestartOptions({ stage: 'review', options: several }, ui, false)).toEqual({ author: 'claude', reviewer: 'codex' });
  expect(asked).toHaveLength(2);
});

test('--lead is sent as lead when the engine lists resumeReviewerOptions, and no flag names an extra reviewer', async () => {
  const requests = await fakeCarrier(['resumeEpic', 'resumeReviewerOptions']);
  vi.spyOn(process.stdout, 'write').mockReturnValue(true);
  expect(await restartCommand(folder!, target, { lead: 'd' })).toBe(0);
  expect(sent(requests)).toEqual([{ cmd: 'resumeEpic', ...target, lead: 'd' }]);
});

test('--lead against an engine that does not list resumeReviewerOptions says so and asks nothing', async () => {
  const requests = await fakeCarrier(['resumeEpic', 'resumeFromStage']);
  const run = restartCommand(folder!, target, { lead: 'claude' });
  await expect(run).rejects.toThrow(CliError);
  await expect(run).rejects.toThrow('too old to restart the lead');
  expect(requests).toEqual([]);
});

test('--author alone against an engine without resumeReviewerOptions is sent as before', async () => {
  const requests = await fakeCarrier(['resumeEpic']);
  vi.spyOn(process.stdout, 'write').mockReturnValue(true);
  expect(await restartCommand(folder!, target, { author: 'codex' })).toBe(0);
  expect(sent(requests)).toEqual([{ cmd: 'resumeEpic', ...target, author: 'codex' }]);
});

test.each(['review', 'fix', 'ship'] as const)('--from %s sends the stage with the epic when the engine lists resumeFromStage', async (from) => {
  const requests = await fakeCarrier(['resumeEpic', 'resumeFromStage']);
  const out = vi.spyOn(process.stdout, 'write').mockReturnValue(true);
  expect(await restartCommand(folder!, target, { from })).toBe(0);
  expect(sent(requests)).toEqual([{ cmd: 'resumeEpic', ...target, from }]);
  expect(out).toHaveBeenCalledWith('Restarted AshuLab/carrier#5\n');
});

test('no --from sends the request as before, whatever the engine lists', async () => {
  const requests = await fakeCarrier(['resumeEpic']);
  vi.spyOn(process.stdout, 'write').mockReturnValue(true);
  expect(await restartCommand(folder!, target, {})).toBe(0);
  expect(sent(requests)).toEqual([{ cmd: 'resumeEpic', ...target }]);
});

test('--extra-rounds is sent as a number with the stage', async () => {
  const requests = await fakeCarrier(['resumeEpic', 'resumeFromStage']);
  vi.spyOn(process.stdout, 'write').mockReturnValue(true);
  expect(await restartCommand(folder!, target, { from: 'fix', extraRounds: 2 })).toBe(0);
  expect(sent(requests)).toEqual([{ cmd: 'resumeEpic', ...target, from: 'fix', extraRounds: 2 }]);
});

test('--extra-rounds against an engine that does not list resumeFromStage says so and asks nothing', async () => {
  const requests = await fakeCarrier(['resumeEpic']);
  const error = (await restartCommand(folder!, target, { extraRounds: 2 }).catch((e) => e)) as CliError;
  expect([error.code, error.message]).toEqual([1, 'The running Carrier is too old to resume from a stage: restart it to get --from.']);
  expect(requests).toEqual([]);
});

test('--from against an engine that does not list resumeFromStage says so and asks nothing', async () => {
  const requests = await fakeCarrier(['resumeEpic']);
  const error = (await restartCommand(folder!, target, { from: 'review' }).catch((e) => e)) as CliError;
  expect([error.code, error.message]).toEqual([1, 'The running Carrier is too old to resume from a stage: restart it to get --from.']);
  expect(requests).toEqual([]);
});

test.each([
  ['epic.unknown', 'Carrier does not know AshuLab/carrier#5. Use the owner/repo#issue that carrier status shows.'],
  ['resume.notStopped', 'AshuLab/carrier#5 is not stopped, so there is nothing to restart.'],
  ['github.unavailable', 'GitHub did not answer, so nothing changed. Try again in a moment.'],
  ['resume.didNotRestart', 'The ready label is back on the issue, but the epic did not start within 30 seconds. The next check will take it.'],
  ['resume.optionUnknown', 'That account is not declared in providers.json. Use a name declared there.'],
  ['resume.noPullRequest', 'AshuLab/carrier#5 has no pull request yet, so it can only be restarted from ship.'],
  ['resume.roleUnknown', 'AshuLab/carrier#5 does not have that reviewer or lead. Name only the roles its configuration has.'],
  ['resume.extraReviewerUnknown', 'AshuLab/carrier#5 does not have that extra reviewer. Name only the keys its configuration has.'],
  ['resume.reviewersWithoutKey', 'AshuLab/carrier#5 was saved before its extra reviewers had names, so it cannot be restarted. Start it again from its issue.'],
  ['resume.extraRoundsNeedStage', '--extra-rounds needs --from review or --from fix: a restart from ship starts the rounds over.'],
  ['resume.extraRoundsNeedReviewLimit', '--extra-rounds grants rounds to an epic that stopped on the review limit, and AshuLab/carrier#5 stopped for another reason.'],
  ['resume.pullRequestNotOpen', "The epic's pull request is not open any more, so nothing was changed. Restart it from ship, or reopen the pull request."],
  ['resume.pullRequestHeadChanged', 'The pull request has a different head than the one Carrier saved, so nothing was changed. Restart it with --from review to review the new head, or from ship to start over.'],
  ['request.internal', 'Carrier refused: refused in other words'],
])('a refusal with the code %s, in whatever words, says what it means and exits 1', async (reason, words) => {
  await fakeCarrier(['resumeEpic', 'resumeFromStage'], () => refusal('refused in other words', reason));
  const error = (await restartCommand(folder!, target, { from: 'review' }).catch((e) => e)) as CliError;
  expect([error.code, error.message]).toEqual([1, words]);
});

test('a refusal without a code is printed with its words', async () => {
  await fakeCarrier(['resumeEpic', 'resumeFromStage'], () => refusal('not stopped'));
  const error = (await restartCommand(folder!, target, { from: 'review' }).catch((e) => e)) as CliError;
  expect([error.code, error.message]).toEqual([1, 'Carrier refused: not stopped']);
});

test('every code the table is keyed by is in the golden list of text codes', () => {
  const codes = Object.keys(JSON.parse(readFileSync(fileURLToPath(new URL('../../../../macos/Tests/Fixtures/text-codes.json', import.meta.url)), 'utf8')));
  expect(Object.keys(refusals).filter((code) => codes.includes(code) === false)).toEqual([]);
});
