import type { StoredEvent } from './mcp.ts';

// What the new agent of a switched session is told about the conversation before it (ADR 0032): a selection of the stored messages, not a summary,
// that travels in the instructions the conversation opens with and never in front of the person's first message.

export const HANDOFF_BUDGET = 16_000;

type Item = { position: number; role: 'person' | 'agent'; text: string; cut: boolean };

const bytes = (text: string) => Buffer.byteLength(text, 'utf8');

/** The text of a handoff that shows `shown` (oldest first) out of `all`; what is not shown whole is named by its position. */
function compose(shown: Item[], all: Item[]): string {
  const whole = new Set(shown.filter((item) => !item.cut).map((item) => item.position));
  const notWhole = all.filter((item) => !whole.has(item.position)).map((item) => item.position);
  return [
    'This conversation continues one that the person had with another agent. Below is a selection of its messages, oldest first, as they were stored: the first message of the person and the newest ones, without reasoning, tool calls or attachments.',
    ...shown.map((item) => `[${item.position}] ${item.role}${item.cut ? ' (cut)' : ''}:\n${item.text}`),
    notWhole.length === 0 ? 'Every message of the conversation is above.' : `Left out or cut, by id: ${notWhole.join(', ')}.`,
    'The `history` tool of the chat MCP reads them whole.',
  ].join('\n\n');
}

/** `item` with the longest prefix of its text that keeps the whole handoff within the budget, cut between characters; undefined when none fits. */
function cutToFit(item: Item, others: Item[], all: Item[], budget: number): Item | undefined {
  const characters = Array.from(item.text);
  const attempt = (count: number): Item => ({ ...item, text: characters.slice(0, count).join(''), cut: true });
  const fits = (count: number) => bytes(compose([...others, attempt(count)].sort((a, b) => a.position - b.position), all)) <= budget;
  if (!fits(1)) return undefined;
  let low = 1; // fits
  let high = characters.length - 1; // the whole text did not fit
  while (low < high) {
    const middle = Math.ceil((low + high) / 2);
    if (fits(middle)) low = middle;
    else high = middle - 1;
  }
  return attempt(low);
}

/**
 * The handoff of a session from its stored events, or undefined when it holds no message of the person or the agent.
 * The first message of the person is always in it, then the newest messages while the whole text, frame included, stays within `budget`
 * in UTF-8 bytes; the first message that does not fit is cut. A command the person invoked is stored as the command, and is shown as such.
 */
export function buildHandoff(events: StoredEvent[], budget = HANDOFF_BUDGET): string | undefined {
  const all: Item[] = events.flatMap((event): Item[] =>
    (event.kind === 'user' || event.kind === 'assistant') && typeof event.data.text === 'string'
      ? [{ position: event.position, role: event.kind === 'user' ? 'person' : 'agent', text: event.data.text, cut: false }]
      : [],
  );
  const first = all.find((item) => item.role === 'person') ?? all[0];
  if (first === undefined) return undefined;

  const fitsWhole = (shown: Item[]) => bytes(compose(shown, all)) <= budget;
  let shown: Item[] = [first];
  if (!fitsWhole(shown)) shown = [cutToFit(first, [], all, budget) ?? { ...first, text: '', cut: true }];
  else {
    for (const item of all.toReversed()) {
      if (item === first) continue;
      const candidate = [...shown, item].sort((a, b) => a.position - b.position);
      if (fitsWhole(candidate)) {
        shown = candidate;
        continue;
      }
      const cut = cutToFit(item, shown, all, budget);
      if (cut !== undefined) shown = [...shown, cut].sort((a, b) => a.position - b.position);
      break;
    }
  }
  return compose(shown, all);
}
