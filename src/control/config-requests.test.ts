import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, test } from 'vitest';
import { addAccountRequest, chatRequest, editAccountRequest, editChatSettingsRequest, projectRequests, removeAccountRequest, setAccountsRequest, setTextGeneratorRequest } from '../chat/server.ts';
import { editBehaviorRequest, engineFileRequests, request, setWatchedReposRequest } from './server.ts';

// The contract with the macOS app for every request that changes a config file (ADR 0053): each request of the two sockets has a golden in macos/Tests/Fixtures (`chat-*.json`,
// `engine-*.json`), each golden's request is accepted by the socket's schema, and the list of the requests is written to config-requests.json for `ContractTests`, which fails
// until the app encodes each one as its golden says. The replies in the goldens are checked where they are written (`config-goldens.test.ts`, `src/chat/server.test.ts`).
// UPDATE_FIXTURES=1 rewrites the list.

const fixtures = fileURLToPath(new URL('../../macos/Tests/Fixtures/', import.meta.url));

const chat = [editChatSettingsRequest, setAccountsRequest, addAccountRequest, editAccountRequest, removeAccountRequest, setTextGeneratorRequest, ...projectRequests].map((schema) => schema.shape.cmd.value).sort();
const engine = [setWatchedReposRequest, editBehaviorRequest, ...engineFileRequests].map((schema) => schema.shape.cmd.value).sort();

/** The requests a golden file holds: one `{ request, reply }`, or a map of them by name. */
function requestsOf(file: string): Record<string, unknown>[] {
  const json: unknown = JSON.parse(readFileSync(`${fixtures}${file}`, 'utf8'));
  if (typeof json !== 'object' || json === null) return [];
  const entries = 'request' in json ? [json] : Object.values(json);
  return entries.flatMap((entry) => (typeof entry === 'object' && entry !== null && 'request' in entry && typeof entry.request === 'object' && entry.request !== null ? [entry.request as Record<string, unknown>] : []));
}

const goldensOf = (prefix: string, cmds: string[]) =>
  readdirSync(fixtures)
    .filter((file) => file.startsWith(prefix) && file.endsWith('.json'))
    .flatMap(requestsOf)
    .filter((golden) => cmds.includes(String(golden.cmd)));

test.each([
  ['chat', chat, chatRequest, 'chat-'],
  ['engine', engine, request, 'engine-'],
] as const)('every config request of the %s socket has a golden that its schema accepts', (_socket, cmds, schema, prefix) => {
  const goldens = goldensOf(prefix, cmds);
  expect(goldens.length).toBeGreaterThan(0);
  expect(cmds.filter((cmd) => goldens.some((golden) => golden.cmd === cmd) === false), 'requests without a golden').toEqual([]);
  for (const golden of goldens) expect(schema.safeParse({ id: 1, ...golden }).success, JSON.stringify(golden)).toBe(true);
});

test('the list of the config requests is config-requests.json, which ContractTests reads', () => {
  const json = `${JSON.stringify({ chat, engine }, null, 2)}\n`;
  if (process.env.UPDATE_FIXTURES === '1') writeFileSync(`${fixtures}config-requests.json`, json);
  expect(json).toBe(readFileSync(`${fixtures}config-requests.json`, 'utf8'));
});
