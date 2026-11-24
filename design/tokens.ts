// The design tokens: parse, validate and emit design/tokens.json (ADR 0054, spec section 7).
// The base layer holds the themes in light and dark, the accent presets and the scales (radius, space, duration).
// The semantic layer names what a colour is for: a hex, a reference such as "{accent.orange}", a light and dark pair of those,
// or the accent shaded (darkened toward black and made translucent).

import { GENERATED_HEADER } from './copy.ts';

/** A refusal of the tokens source: its message names the token. */
export class TokenError extends Error {}

export interface ThemeColors {
  window: string;
  sidebar: string;
  accent: string | null;
}

export interface Shade {
  darken: number;
  alpha: number;
}

export type SemanticValue = { kind: 'color'; light: string; dark: string } | { kind: 'shade'; light: Shade; dark: Shade };

export interface CompiledTokens {
  themes: [string, { light: ThemeColors; dark: ThemeColors }][];
  accents: [string, string][];
  scales: [Scale, [string, number][]][];
  semantic: [string, [string, SemanticValue][]][];
}

const SCALES = { radius: 'px', space: 'px', duration: 's' } as const;
type Scale = keyof typeof SCALES;

const NAME = /^[a-z][A-Za-z0-9]*$/;
const HEX = /^#[0-9a-f]{6}$/;
const REFERENCE = /^\{([A-Za-z0-9.]+)\}$/;

type Json = unknown;

function isObject(value: Json): value is Record<string, Json> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function object(value: Json, where: string): Record<string, Json> {
  if (isObject(value) === false) throw new TokenError(`${where} is not an object`);
  return value as Record<string, Json>;
}

function names(table: Record<string, Json>, where: string): string[] {
  const keys = Object.keys(table);
  for (const key of keys) {
    if (NAME.test(key) === false) throw new TokenError(`${where}: "${key}" is not a camelCase name`);
  }
  return keys;
}

function hex(value: Json, where: string): string {
  if (typeof value !== 'string' || HEX.test(value) === false) throw new TokenError(`${where} is not a #rrggbb hex in lower case`);
  return value;
}

function themeColors(value: Json, where: string): ThemeColors {
  const table = object(value, where);
  for (const key of Object.keys(table)) {
    if (['window', 'sidebar', 'accent'].includes(key) === false) throw new TokenError(`${where}: unknown key "${key}"`);
  }
  return {
    window: hex(table.window, `${where}.window`),
    sidebar: hex(table.sidebar, `${where}.sidebar`),
    accent: table.accent === null ? null : hex(table.accent, `${where}.accent`),
  };
}

function number(value: Json, where: string, max = Infinity): number {
  if (typeof value !== 'number' || Number.isFinite(value) === false || value < 0 || value > max) throw new TokenError(`${where} is not a number from 0 to ${max}`);
  return value;
}

function shadeOf(value: Json, where: string): Shade {
  const table = object(value, where);
  const keys = Object.keys(table);
  for (const key of keys) {
    if (key !== 'darken' && key !== 'alpha') throw new TokenError(`${where}: unknown key "${key}"`);
  }
  return {
    darken: table.darken === undefined ? 0 : number(table.darken, `${where}.darken`, 1),
    alpha: table.alpha === undefined ? 1 : number(table.alpha, `${where}.alpha`, 1),
  };
}

function isShade(value: Json): boolean {
  return isObject(value) && ('darken' in value || 'alpha' in value);
}

function lookup(root: Record<string, Json>, path: string, where: string): Json {
  let at: Json = root;
  for (const part of path.split('.')) {
    if (isObject(at) === false || part in at === false) throw new TokenError(`${where}: "{${path}}" points at nothing`);
    at = (at as Record<string, Json>)[part];
  }
  return at;
}

/** The value of a semantic entry or of a side of one, with every reference followed. */
function resolve(root: Record<string, Json>, value: Json, where: string, seen: string[] = []): SemanticValue {
  if (typeof value === 'string') {
    const reference = REFERENCE.exec(value);
    if (reference === null) {
      const color = hex(value, where);
      return { kind: 'color', light: color, dark: color };
    }
    const path = reference[1]!;
    if (seen.includes(path)) throw new TokenError(`${where}: "{${path}}" refers back to itself`);
    return resolve(root, lookup(root, path, where), `${where} -> ${path}`, [...seen, path]);
  }
  if (isShade(value)) {
    const shade = shadeOf(value, where);
    return { kind: 'shade', light: shade, dark: shade };
  }
  const table = object(value, where);
  const keys = Object.keys(table).sort().join(',');
  if (keys !== 'dark,light') throw new TokenError(`${where} is neither a hex, a reference, a shade nor a pair with "light" and "dark"`);
  const light = resolve(root, table.light, `${where}.light`, seen);
  const dark = resolve(root, table.dark, `${where}.dark`, seen);
  if (light.kind === 'color' && dark.kind === 'color') return { kind: 'color', light: light.light, dark: dark.dark };
  if (light.kind === 'shade' && dark.kind === 'shade') return { kind: 'shade', light: light.light, dark: dark.dark };
  throw new TokenError(`${where}: light and dark must both be colours or both be shades`);
}

/** The tokens as the emitters read them; a source the layers do not allow fails, naming the token. */
export function compileTokens(source: unknown): CompiledTokens {
  const root = object(source, 'tokens');
  for (const key of Object.keys(root)) {
    if (['theme', 'accent', 'semantic', ...Object.keys(SCALES)].includes(key) === false) throw new TokenError(`tokens: unknown section "${key}"`);
  }
  const theme = object(root.theme, 'theme');
  const themes = names(theme, 'theme').map((name): CompiledTokens['themes'][number] => {
    const versions = object(theme[name], `theme.${name}`);
    return [name, { light: themeColors(versions.light, `theme.${name}.light`), dark: themeColors(versions.dark, `theme.${name}.dark`) }];
  });
  const accent = object(root.accent, 'accent');
  const accents = names(accent, 'accent').map((name): [string, string] => [name, hex(accent[name], `accent.${name}`)]);
  const scales = (Object.keys(SCALES) as Scale[])
    .filter((scale) => root[scale] !== undefined)
    .map((scale): CompiledTokens['scales'][number] => {
      const table = object(root[scale], scale);
      return [scale, names(table, scale).map((name): [string, number] => [name, number(table[name], `${scale}.${name}`)])];
    });
  const semanticRoot = root.semantic === undefined ? {} : object(root.semantic, 'semantic');
  const semantic = names(semanticRoot, 'semantic').map((group): CompiledTokens['semantic'][number] => {
    const table = object(semanticRoot[group], `semantic.${group}`);
    return [group, names(table, `semantic.${group}`).map((name): [string, SemanticValue] => [name, resolve(root, table[name], `semantic.${group}.${name}`)])];
  });
  return { themes, accents, scales, semantic };
}

// Swift

const capitalized = (name: string): string => name.charAt(0).toUpperCase() + name.slice(1);
const swiftHex = (value: string): string => `0x${value.slice(1)}`;
const swiftShade = (shade: Shade): string => `AccentShade(darken: ${shade.darken}, alpha: ${shade.alpha})`;

const SWIFT_TYPES = `/// One value for each of the two versions the color scheme picks between.
public struct SchemePair<Value: Sendable>: Sendable {
    public let light: Value
    public let dark: Value
}

/// What a theme paints in one version: the window, the sidebar and the accent (nil keeps the Mac's own).
public struct ThemeColors: Sendable {
    public let window: UInt32
    public let sidebar: UInt32
    public let accent: UInt32?
}

/// The accent darkened toward black by \`darken\` (0 to 1) and drawn at \`alpha\` opacity.
public struct AccentShade: Equatable, Sendable {
    public let darken: Double
    public let alpha: Double
}
`;

function swiftColors(colors: ThemeColors): string {
  return `ThemeColors(window: ${swiftHex(colors.window)}, sidebar: ${swiftHex(colors.sidebar)}, accent: ${colors.accent === null ? 'nil' : swiftHex(colors.accent)})`;
}

/** Tokens.generated.swift: the themes, the accent presets, the scales and the semantic colours as constants. */
export function emitTokensSwift(tokens: CompiledTokens): string {
  const lines = [GENERATED_HEADER, '', SWIFT_TYPES, 'public enum Tokens {'];
  lines.push('    /// The themes by name, each in light and dark.', '    public static let themes: [String: SchemePair<ThemeColors>] = [');
  for (const [name, versions] of tokens.themes) {
    lines.push(`        "${name}": SchemePair(light: ${swiftColors(versions.light)}, dark: ${swiftColors(versions.dark)}),`);
  }
  lines.push('    ]', '', '    /// The accent presets, in the order the picker shows them.', '    public static let accents: [(name: String, hex: UInt32)] = [');
  for (const [name, value] of tokens.accents) lines.push(`        ("${name}", ${swiftHex(value)}),`);
  lines.push('    ]');
  for (const [scale, entries] of tokens.scales) {
    lines.push('', `    public enum ${capitalized(scale)} {`);
    for (const [name, value] of entries) lines.push(`        public static let ${name}: Double = ${value}`);
    lines.push('    }');
  }
  for (const [group, entries] of tokens.semantic) {
    lines.push('', `    public enum ${capitalized(group)} {`);
    for (const [name, value] of entries) {
      if (value.kind === 'color') lines.push(`        public static let ${name} = SchemePair<UInt32>(light: ${swiftHex(value.light)}, dark: ${swiftHex(value.dark)})`);
      else lines.push(`        public static let ${name} = SchemePair<AccentShade>(light: ${swiftShade(value.light)}, dark: ${swiftShade(value.dark)})`);
    }
    lines.push('    }');
  }
  lines.push('}', '');
  return lines.join('\n');
}

// TypeScript

const tsShade = (shade: Shade): string => `{ darken: ${shade.darken}, alpha: ${shade.alpha} }`;
const tsColors = (colors: ThemeColors): string =>
  `{ window: '${colors.window}', sidebar: '${colors.sidebar}', accent: ${colors.accent === null ? 'null' : `'${colors.accent}'`} }`;

/** tokens.ts for the web: the same tables as constants. */
export function emitTokensTypeScript(tokens: CompiledTokens): string {
  const lines = [
    GENERATED_HEADER,
    '',
    'export interface ThemeColors { window: string; sidebar: string; accent: string | null }',
    '',
    'export interface Shade { darken: number; alpha: number }',
    '',
    'export const themes = {',
  ];
  for (const [name, versions] of tokens.themes) lines.push(`  ${name}: { light: ${tsColors(versions.light)}, dark: ${tsColors(versions.dark)} },`);
  lines.push('} as const;', '', 'export const accents = {');
  for (const [name, value] of tokens.accents) lines.push(`  ${name}: '${value}',`);
  lines.push('} as const;');
  for (const [scale, entries] of tokens.scales) {
    lines.push('', `export const ${scale} = {`);
    for (const [name, value] of entries) lines.push(`  ${name}: ${value},`);
    lines.push('} as const;');
  }
  lines.push('', 'export const semantic = {');
  for (const [group, entries] of tokens.semantic) {
    lines.push(`  ${group}: {`);
    for (const [name, value] of entries) {
      if (value.kind === 'color') lines.push(`    ${name}: { light: '${value.light}', dark: '${value.dark}' },`);
      else lines.push(`    ${name}: { light: ${tsShade(value.light)}, dark: ${tsShade(value.dark)} },`);
    }
    lines.push('  },');
  }
  lines.push('} as const;', '');
  return lines.join('\n');
}

// CSS

const CSS_HEADER = `/* ${GENERATED_HEADER.slice(3)} */`;

/** The accent shaded, as a CSS color: darkened toward black, then made translucent. */
function cssShade(shade: Shade): string {
  const darkened = shade.darken === 0 ? 'var(--accent)' : `color-mix(in srgb, var(--accent) ${percent(1 - shade.darken)}, black)`;
  return shade.alpha === 1 ? darkened : `color-mix(in srgb, ${darkened} ${percent(shade.alpha)}, transparent)`;
}

const percent = (fraction: number): string => `${Math.round(fraction * 10000) / 100}%`;
const kebab = (name: string): string => name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);

function cssBlock(selector: string, declarations: string[]): string[] {
  return declarations.length === 0 ? [] : [`${selector} {`, ...declarations.map((line) => `  ${line}`), '}', ''];
}

/**
 * tokens.css for the web: custom properties.
 * The light values sit on `:root` and the dark ones under `[data-scheme='dark']`; a theme is `[data-theme='name']`, with its dark version under it.
 * A theme with no accent of its own declares none, so the page keeps the one it had.
 */
export function emitTokensCss(tokens: CompiledTokens): string {
  const lines = [CSS_HEADER, ''];
  const light: string[] = tokens.accents.map(([name, value]) => `--accent-${kebab(name)}: ${value};`);
  const dark: string[] = [];
  for (const [scale, entries] of tokens.scales) {
    for (const [name, value] of entries) light.push(`--${scale}-${kebab(name)}: ${value}${SCALES[scale]};`);
  }
  for (const [group, entries] of tokens.semantic) {
    for (const [name, value] of entries) {
      const property = `--${kebab(group)}-${kebab(name)}`;
      const [lightValue, darkValue] = value.kind === 'color' ? [value.light, value.dark] : [cssShade(value.light), cssShade(value.dark)];
      light.push(`${property}: ${lightValue};`);
      if (darkValue !== lightValue) dark.push(`${property}: ${darkValue};`);
    }
  }
  lines.push(...cssBlock(':root', light), ...cssBlock("[data-scheme='dark']", dark));
  const colors = (version: ThemeColors): string[] => [
    `--window: ${version.window};`,
    `--sidebar: ${version.sidebar};`,
    ...(version.accent === null ? [] : [`--accent: ${version.accent};`]),
  ];
  for (const [name, versions] of tokens.themes) {
    lines.push(...cssBlock(`[data-theme='${name}']`, colors(versions.light)), ...cssBlock(`[data-theme='${name}'][data-scheme='dark']`, colors(versions.dark)));
  }
  return lines.join('\n');
}
