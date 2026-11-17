import { buildHandoff, load, type Item } from './lib.ts';
const items = load<Item[]>(process.argv[2]!);
const h = buildHandoff(items);
console.log({ messageBytes: h.messageBytes, textBytes: h.textBytes, included: h.included, cut: h.cut, omitted: h.omitted });
for (const i of items) if (i.kind === 'user' || i.kind === 'assistant') console.log(i.position, i.kind, Buffer.byteLength(i.text));
console.log(h.text.slice(-900));
