import { expect, test } from 'vitest';
import { quietUi } from '../wizard/testing.ts';
import { journaled } from './journal.ts';
import { Back, type Ui } from './types.ts';

/** A scripted Ui that throws `Back` the first time the question at `index` (counting the questions shown) is asked, and records what it shows and the starting point it is given. */
function scripted(backAt: number[] = [], answers: Record<string, string | boolean> = {}) {
  const { ui, asked, notes } = quietUi(answers);
  let shown = 0;
  const starts: Record<string, unknown> = {};
  const gate = async (message: string, start: unknown) => {
    starts[message] = start;
    if (backAt.includes(shown++)) throw new Back();
  };
  const spy: Ui = {
    ...ui,
    select: async (o) => (await gate(o.message, o.initialValue), ui.select(o)),
    confirm: async (m, i) => (await gate(m, i), ui.confirm(m, i)),
    text: async (o) => (await gate(o.message, o.defaultValue), ui.text(o)),
    multiselect: async (o) => (await gate(o.message, o.initialValues), ui.multiselect(o)),
  };
  return { spy, asked, notes, starts };
}

/** What the caller of a flow does with a `Back`: drop one answer and run again. */
async function run<T>(journal: ReturnType<typeof journaled>, flow: () => Promise<T>) {
  for (;;) {
    try {
      return await flow();
    } catch (error) {
      if (!(error instanceof Back) || journal.back() === 'leave') throw error;
    }
  }
}

const options = [{ value: 'a', label: 'A' }, { value: 'b', label: 'B' }];

test('after a Back the questions before it are answered from the journal and show nothing, and the dropped one starts from its old answer', async () => {
  const { spy, asked, starts } = scripted([2], { First: 'b', 'Second?': false });
  const journal = journaled(spy);
  const flow = async () => {
    journal.at('author');
    return [await journal.ui.select({ message: 'First', options }), await journal.ui.confirm('Second?', true), await journal.ui.confirm('Third?', true)];
  };
  expect(await run(journal, flow)).toEqual(['b', false, true]);
  expect(asked).toEqual(['First', 'Second?', 'Second?', 'Third?']); // First is not shown again; Second? is, because Esc at Third? dropped it
  expect(starts['Second?']).toBe(false); // starts from the answer it had
});

test('a step back across a block edge lands on the last question of the previous block', async () => {
  const { spy, asked } = scripted([2]);
  const journal = journaled(spy);
  const flow = async () => {
    journal.at('author');
    await journal.ui.confirm('author one', true);
    await journal.ui.confirm('author two', true);
    journal.at('reviewer');
    await journal.ui.confirm('reviewer one', true);
  };
  await run(journal, flow);
  expect(asked).toEqual(['author one', 'author two', 'author two', 'reviewer one']);
});

test('Esc at the first question has nothing to go back to', async () => {
  const { spy } = scripted([0]);
  const journal = journaled(spy);
  await expect(run(journal, () => journal.ui.confirm('first', true))).rejects.toBeInstanceOf(Back);
});

test('the results of busy and of a once step are kept: going back across them runs them zero more times', async () => {
  const { spy } = scripted([2]);
  const journal = journaled(spy);
  let listed = 0;
  let added = 0;
  const flow = async () => {
    await journal.ui.confirm('before', true);
    await journal.ui.busy('Reading repos', async () => ++listed);
    journal.once('add a bot', () => ++added);
    await journal.ui.confirm('after', true);
  };
  await run(journal, flow);
  expect([listed, added]).toEqual([1, 1]);
});

test('an answer whose option no longer exists is asked again', async () => {
  const { spy, asked } = scripted([], { Profile: 'b' });
  const journal = journaled(spy);
  const flow = async (shown: typeof options) => {
    journal.at('author');
    return journal.ui.select({ message: 'Profile', options: shown });
  };
  expect(await flow(options)).toBe('b');
  journal.jump('reviewer'); // another block: the answer stays
  expect(await flow(options)).toBe('b');
  expect(asked).toEqual(['Profile']);
  journal.jump('reviewer');
  await flow([options[0]!]); // 'b' is not among the options any more: asked again
  expect(asked).toEqual(['Profile', 'Profile']);
});

test('a jump drops one block and keeps the others', async () => {
  const { spy, asked, starts } = scripted([], { 'author q': 'x', 'reviewer q': 'y' });
  const journal = journaled(spy);
  const flow = async () => {
    journal.at('author');
    await journal.ui.text({ message: 'author q' });
    journal.at('reviewer');
    await journal.ui.text({ message: 'reviewer q' });
  };
  await flow();
  journal.jump('reviewer');
  await flow();
  expect(asked).toEqual(['author q', 'reviewer q', 'reviewer q']);
  expect(starts['reviewer q']).toBe('y');
});

test('what the flow prints while replaying is shown only if the next question is asked for real', async () => {
  const { spy, notes } = scripted([2]);
  const journal = journaled(spy);
  const flow = async () => {
    journal.ui.note('one', 'T');
    await journal.ui.confirm('a', true);
    journal.ui.note('two', 'T');
    await journal.ui.confirm('b', true);
    journal.ui.note('three', 'T');
    await journal.ui.confirm('c', true);
  };
  await run(journal, flow);
  expect(notes.map((n) => n.message)).toEqual(['one', 'two', 'three', 'two', 'three']); // after the Back, 'one' is not repeated: only what leads to the question asked again comes back
});

test('Esc at the first question asked after a jump abandons the jump with the block as it was, and Esc deeper in the block goes back one question', async () => {
  const { ui } = quietUi();
  const asked: string[] = [];
  const spy: Ui = {
    ...ui,
    confirm: async (m, i) => {
      asked.push(m);
      if (m === 'reviewer one' && asked.filter((q) => q === m).length === 2) throw new Back();
      return i ?? true;
    },
  };
  const journal = journaled(spy);
  const flow = async () => {
    journal.at('author');
    await journal.ui.confirm('author one', true);
    journal.at('reviewer');
    await journal.ui.confirm('reviewer one', false);
  };
  await flow();
  journal.settled();
  journal.jump('reviewer');
  await expect(flow()).rejects.toBeInstanceOf(Back); // Esc at "reviewer one", the first question asked for real after the jump
  expect(journal.back()).toBe('recap');
  await flow(); // the recap's pass: every answer, the reviewer's included, comes from the journal
  expect(asked).toEqual(['author one', 'reviewer one', 'reviewer one']);
  expect(journal.back()).toBe('question'); // once settled, Esc is one question back as always
});
