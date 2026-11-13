import type { Tokens } from './pricing.ts';

// Antigravity keeps one SQLite file per conversation. `gen_metadata` and `steps` hold protobuf blobs; this reads only the fields
// that carry usage, after pingdotgg/t3code's antigravityUsageReader.ts (docs/research/codexbar-usage-fetching.md).

type Value = number | Uint8Array;
type Fields = Map<number, Value[]>;

/** The fields of one protobuf message, by number. Throws on a message that is cut short or malformed. */
export function protoFields(bytes: Uint8Array): Fields {
  const fields: Fields = new Map();
  let at = 0;
  const varint = (): number => {
    let value = 0;
    for (let shift = 0; shift < 63; shift += 7) {
      const byte = bytes[at++];
      if (byte === undefined) throw new Error('truncated varint');
      value += (byte & 127) * 2 ** shift;
      if (byte < 128) return value;
    }
    throw new Error('varint too long');
  };
  while (at < bytes.length) {
    const tag = varint();
    const number = Math.floor(tag / 8);
    const wire = tag % 8;
    if (number === 0) throw new Error('bad field number');
    let value: Value;
    if (wire === 0) value = varint();
    else if (wire === 1 || wire === 5 || wire === 2) {
      const length = wire === 2 ? varint() : wire === 1 ? 8 : 4;
      if (length > bytes.length - at) throw new Error('truncated field');
      const slice = bytes.subarray(at, at + length);
      at += length;
      if (wire !== 2) continue; // fixed-width values carry nothing this reads
      value = slice;
    } else throw new Error('unsupported wire type');
    fields.set(number, [...(fields.get(number) ?? []), value]);
  }
  return fields;
}

const numberAt = (fields: Fields, key: number) => {
  const value = fields.get(key)?.[0];
  return typeof value === 'number' ? value : 0;
};
const bytesAt = (fields: Fields, key: number) => {
  const value = fields.get(key)?.[0];
  return value instanceof Uint8Array ? value : undefined;
};
const nested = (fields: Fields, key: number): Fields => {
  const bytes = bytesAt(fields, key);
  return bytes === undefined ? new Map() : protoFields(bytes);
};
const textAt = (fields: Fields, key: number) => {
  const bytes = bytesAt(fields, key);
  return bytes === undefined ? '' : new TextDecoder('utf-8', { fatal: true }).decode(bytes).trim();
};
const timestamp = (fields: Fields) => {
  const seconds = numberAt(fields, 1);
  return seconds > 0 ? seconds * 1000 + Math.floor(numberAt(fields, 2) / 1_000_000) : undefined;
};
const modelName = (name: string) => name.toLowerCase().replace(/\s*\(([^)]*)\)\s*$/, '-$1').replace(/\s+/g, '-');

export interface AgyRecord {
  at: number;
  model: string;
  tokens: Tokens;
}

/** Everything a database can be asked: the rows of a query, one at a time (a row can hold megabytes of context). */
export interface RowSource {
  hasTable(name: string): boolean;
  rows(sql: string): Iterable<Record<string, unknown>>;
}

function usageOf(usage: Fields): Tokens {
  const output = Math.max(numberAt(usage, 3), numberAt(usage, 9) + numberAt(usage, 10));
  return { input: numberAt(usage, 2), cachedInput: numberAt(usage, 5), cacheWrite: numberAt(usage, 4), output, reasoning: Math.min(output, numberAt(usage, 9)) };
}

/** The usage of one blob: the model, the time, and each call it made (the first and its retries, which cost too). */
function readBlob(blob: unknown, isStep: boolean, fallbackAt: number) {
  if (!(blob instanceof Uint8Array)) throw new Error('not a blob');
  const root = protoFields(blob);
  const data = isStep ? root : nested(root, 1);
  if (isStep === false && bytesAt(root, 1) === undefined) throw new Error('no generation metadata');
  const model = isStep ? nested(data, 24) : data;
  const names = [textAt(model, isStep ? 12 : 19), textAt(model, isStep ? 8 : 21)].map(modelName);
  const modelId = numberAt(model, isStep ? 1 : 3);
  const at = (isStep ? (timestamp(nested(data, 8)) ?? timestamp(nested(data, 1))) : timestamp(nested(nested(data, 9), 4))) ?? fallbackAt;
  const usages: Fields[] = [];
  const first = bytesAt(data, isStep ? 9 : 4);
  if (first !== undefined) usages.push(protoFields(first));
  for (const retry of data.get(isStep ? 28 : 17) ?? []) {
    if (!(retry instanceof Uint8Array)) throw new Error('bad retry');
    const usage = bytesAt(protoFields(retry), 2);
    if (usage !== undefined) usages.push(protoFields(usage));
  }
  return { at, name: names.find((n) => /^(?:gemini-\d|claude-|gpt-)/.test(n)) ?? names.find((n) => n !== '' && !/^model[_-]/.test(n)) ?? (modelId > 0 ? `antigravity-model-${modelId}` : 'antigravity-unknown'), usages };
}

/**
 * The calls one conversation database holds. A call that shows up as a generation and as a step, or twice as a step, shares one of
 * its ids (fields 11, 12, 7) and is counted once, at its largest. Throws when the file is not a readable Antigravity database.
 */
export function readAgyRecords(source: RowSource, fallbackAt: number): AgyRecord[] {
  if (source.hasTable('gen_metadata') === false && source.hasTable('steps') === false) throw new Error('not an Antigravity database');
  const found = new Map<string, AgyRecord>();
  const all: AgyRecord[] = [];
  const queries = [
    { sql: 'select data from gen_metadata', table: 'gen_metadata', column: 'data', isStep: false },
    { sql: 'select metadata from steps', table: 'steps', column: 'metadata', isStep: true },
  ];
  for (const { sql, table, column, isStep } of queries) {
    if (source.hasTable(table) === false) continue;
    for (const row of source.rows(sql)) {
      if (row[column] === null) continue;
      const { at, name, usages } = readBlob(row[column], isStep, fallbackAt);
      for (const usage of usages) {
        const tokens = usageOf(usage);
        if (tokens.input + tokens.cachedInput + tokens.cacheWrite + tokens.output === 0) continue;
        const keys = ([11, 12, 7] as const).flatMap((key) => {
          const id = textAt(usage, key);
          return id === '' ? [] : [`${key}:${id}`];
        });
        const same = keys.map((key) => found.get(key)).find((record) => record !== undefined);
        const record = same ?? { at, model: name, tokens };
        if (same === undefined) all.push(record);
        else for (const channel of Object.keys(tokens) as (keyof Tokens)[]) record.tokens[channel] = Math.max(record.tokens[channel], tokens[channel]);
        for (const key of keys) found.set(key, record);
      }
    }
  }
  return all;
}
