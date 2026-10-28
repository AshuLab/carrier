import { expect, test } from 'vitest';
import type { Ui } from '../../prompts/types.ts';
import { askOptions } from './restart.ts';

const options = { names: ['claude', 'codex'], author: 'claude', reviewer: 'codex', choiceDeadline: null };

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
  expect(await askOptions({ stage: 'fix', options }, ui)).toEqual({ author: 'codex', reviewer: 'codex' });
  expect(asked).toEqual([
    { message: 'Option for the author', initialValue: 'claude', hints: { claude: 'current, failed', codex: undefined } },
    { message: 'Option for the reviewer', initialValue: 'codex', hints: { claude: undefined, codex: 'current' } },
  ]);
});

test('it marks the reviewer when the epic stopped in review', async () => {
  const { ui, asked } = scripted();
  expect(await askOptions({ stage: 'review', options }, ui)).toEqual({ author: 'claude', reviewer: 'codex' });
  expect(asked.map((q) => q.hints)).toEqual([{ claude: 'current', codex: undefined }, { claude: undefined, codex: 'current, failed' }]);
});

test('it asks nothing of an epic with a single option, none, or one Carrier does not list', async () => {
  const { ui, asked } = scripted();
  expect(await askOptions({ stage: 'ship', options: { ...options, names: ['claude'] } }, ui)).toEqual({});
  expect(await askOptions({ stage: 'ship', options: undefined }, ui)).toEqual({});
  expect(await askOptions(undefined, ui)).toEqual({});
  expect(asked).toEqual([]);
});
