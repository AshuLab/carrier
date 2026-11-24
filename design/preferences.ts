// The app's preferences: parse, validate and emit design/preferences.json (ADR 0054, spec section 7).
// Each key has a type (`bool`, `int`, `double`, `string`, `map` of strings or doubles, or an enum's `values`), a default (none when `optional`)
// and the Settings page whose Reset clears it ("none" for a key no Reset clears). The key names are the ones saved in user defaults.

import { GENERATED_HEADER } from './copy.ts';

/** A refusal of the preferences source: its message names the key. */
export class PreferenceError extends Error {}

/** The cases of `SettingsPage`, and "none" for the keys that no page's Reset clears. */
export const PAGES = [
  'general', 'providers', 'appearance', 'notifications', 'keybindings', 'dictation', 'keepAwake', 'chat', 'sessions', 'projects', 'sidebar', 'terminal',
  'agents', 'watching', 'behavior', 'engine', 'health', 'about', 'none',
] as const;

const TYPES = ['bool', 'int', 'double', 'string', 'map'] as const;
const FIELDS = ['type', 'values', 'swift', 'of', 'optional', 'default', 'page'];

export interface Preference {
  key: string;
  /** The key as a Swift property: `appearance.mono.size` is `appearanceMonoSize`. */
  property: string;
  kind: (typeof TYPES)[number] | 'values';
  /** The words of an enum, in the order the source gives them. */
  values: string[];
  /** The Swift enum that reads `values`, when there is one; a `values` key without it is a string. */
  swift: string | null;
  /** What a `map` holds. */
  of: 'string' | 'double';
  optional: boolean;
  default: unknown;
  page: (typeof PAGES)[number];
}

const KEY = /^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)*$/;
const SWIFT_NAME = /^[A-Z][A-Za-z0-9]*$/;

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function fits(preference: Preference, value: unknown): boolean {
  switch (preference.kind) {
    case 'bool': return typeof value === 'boolean';
    case 'int': return Number.isInteger(value);
    case 'double': return typeof value === 'number' && Number.isFinite(value);
    case 'string': return typeof value === 'string';
    case 'values': return typeof value === 'string' && preference.values.includes(value);
    case 'map': return isObject(value) && Object.keys(value).length === 0;
  }
}

/** The preferences, in the order of the source; refuses what the generator cannot type, naming the key. */
export function compilePreferences(source: unknown): Preference[] {
  if (isObject(source) === false) throw new PreferenceError('design/preferences.json is not an object of preferences');
  const properties = new Set<string>();
  return Object.entries(source).map(([key, entry]) => {
    const refuse = (message: string): never => {
      throw new PreferenceError(`preference "${key}": ${message}`);
    };
    if (KEY.test(key) === false) refuse('the name is not dotted camelCase words');
    if (isObject(entry) === false) return refuse('is not an object');
    const table = entry as Record<string, unknown>;
    for (const field of Object.keys(table)) if (FIELDS.includes(field) === false) refuse(`unknown field "${field}"`);

    const { type, values, swift, of, page } = table;
    let kind: Preference['kind'];
    if (values !== undefined) {
      if (type !== undefined) refuse('has both "type" and "values"');
      if (Array.isArray(values) === false || values.length === 0 || values.some((value) => typeof value !== 'string')) refuse('"values" is not a list of strings');
      kind = 'values';
    } else {
      if (TYPES.includes(type as (typeof TYPES)[number]) === false) refuse(`unknown type ${JSON.stringify(type)}`);
      kind = type as (typeof TYPES)[number];
    }
    if (swift !== undefined && (kind !== 'values' || typeof swift !== 'string' || SWIFT_NAME.test(swift) === false)) refuse('"swift" is a Swift type name and goes with "values"');
    if (of !== undefined && (kind !== 'map' || (of !== 'string' && of !== 'double'))) refuse('"of" is "string" or "double" and goes with a map');
    if (kind === 'map' && of === undefined) refuse('a map says what it holds with "of"');
    if (table.optional !== undefined && table.optional !== true) refuse('"optional" is true or absent');
    if (typeof page !== 'string' || PAGES.includes(page as (typeof PAGES)[number]) === false) refuse(`has no Settings page (one of ${PAGES.join(', ')})`);

    const preference: Preference = {
      key,
      property: key.split('.').map((word, index) => (index === 0 ? word : word.charAt(0).toUpperCase() + word.slice(1))).join(''),
      kind,
      values: (values as string[] | undefined) ?? [],
      swift: (swift as string | undefined) ?? null,
      of: (of as 'string' | 'double' | undefined) ?? 'string',
      optional: table.optional === true,
      default: table.default,
      page: page as Preference['page'],
    };
    if (preference.optional) {
      if (table.default !== undefined) refuse('is optional, so it has no default');
    } else if (table.default === undefined) refuse('has no default');
    else if (fits(preference, table.default) === false) refuse(`default ${JSON.stringify(table.default)} is not ${kind === 'values' ? `one of ${preference.values.join(', ')}` : kind === 'map' ? 'an empty object' : `a ${kind}`}`);
    if (properties.has(preference.property)) refuse(`makes the Swift name "${preference.property}" again`);
    properties.add(preference.property);
    return preference;
  });
}

function swiftType(preference: Preference): string {
  switch (preference.kind) {
    case 'bool': return 'Bool';
    case 'int': return 'Int';
    case 'double': return 'Double';
    case 'string': return 'String';
    case 'values': return preference.swift ?? 'String';
    case 'map': return `[String: ${preference.of === 'double' ? 'Double' : 'String'}]`;
  }
}

function swiftDefault(preference: Preference): string {
  if (preference.kind === 'map') return '[:]';
  const literal = JSON.stringify(preference.default);
  return preference.swift === null ? literal : `${preference.swift}(rawValue: ${literal})!`;
}

const SWIFT_PRELUDE = `import Foundation

/// A preference and the value it reads as while none is saved.
public struct PreferenceKey<Value> {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

/// A preference with no value of its own: absent means "as the system or the theme says".
public struct OptionalPreferenceKey<Value> {
    public let name: String

    public init(_ name: String) { self.name = name }
}
`;

/** Preferences.generated.swift: a typed key per preference and the keys each page's Reset clears. */
export function emitPreferencesSwift(preferences: Preference[]): string {
  const lines = [GENERATED_HEADER, '', SWIFT_PRELUDE];
  const enums = [...new Set(preferences.flatMap((preference) => (preference.swift === null ? [] : [preference.swift])))];
  for (const name of enums) lines.push(`extension ${name}: PreferenceValue {}`);
  if (enums.length > 0) lines.push('');
  lines.push('public enum Preference {');
  for (const preference of preferences) {
    const type = swiftType(preference);
    lines.push(
      preference.optional
        ? `    public static let ${preference.property} = OptionalPreferenceKey<${type}>(${JSON.stringify(preference.key)})`
        : `    public static let ${preference.property} = PreferenceKey<${type}>(${JSON.stringify(preference.key)}, default: ${swiftDefault(preference)})`,
    );
  }
  lines.push('', '    /// The names each page\'s Reset takes out of user defaults, so the page reads as its defaults again.', '    public static let resetNames: [SettingsPage: [String]] = [');
  for (const page of PAGES.filter((name) => name !== 'none')) {
    const members = preferences.filter((preference) => preference.page === page);
    if (members.length > 0) lines.push(`        .${page}: [${members.map((preference) => `${preference.property}.name`).join(', ')}],`);
  }
  lines.push(
    '    ]',
    '',
    '    /// Takes the preferences of one page out, and no other.',
    '    public static func reset(_ page: SettingsPage, in defaults: UserDefaults = .standard) {',
    '        for name in resetNames[page] ?? [] { defaults.removeObject(forKey: name) }',
    '    }',
    '}',
    '',
  );
  return lines.join('\n');
}

function tsType(preference: Preference): string {
  switch (preference.kind) {
    case 'bool': return 'boolean';
    case 'int':
    case 'double': return 'number';
    case 'string': return 'string';
    case 'values': return preference.values.map((value) => JSON.stringify(value)).join(' | ');
    case 'map': return `Record<string, ${preference.of === 'double' ? 'number' : 'string'}>`;
  }
}

/** preferences.ts for the web: the value of each key, the defaults and the page of each. */
export function emitPreferencesTypeScript(preferences: Preference[]): string {
  const quoted = (key: string): string => JSON.stringify(key);
  const lines = [GENERATED_HEADER, '', '/** What each preference holds; an optional one is absent until it is set. */', 'export interface Preferences {'];
  for (const preference of preferences) lines.push(`  ${quoted(preference.key)}${preference.optional ? '?' : ''}: ${tsType(preference)};`);
  lines.push('}', '', '/** What each preference reads as while none is saved. */', 'export const preferenceDefaults = {');
  for (const preference of preferences.filter((entry) => entry.optional === false)) {
    lines.push(`  ${quoted(preference.key)}: ${preference.kind === 'map' ? '{}' : JSON.stringify(preference.default)},`);
  }
  lines.push('} as const;', '', "/** The Settings page whose Reset clears each preference; 'none' when no page does. */", 'export const preferencePages = {');
  for (const preference of preferences) lines.push(`  ${quoted(preference.key)}: ${JSON.stringify(preference.page).replaceAll('"', "'")},`);
  lines.push('} as const;', '');
  return lines.join('\n');
}
