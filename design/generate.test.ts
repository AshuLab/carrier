import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { afterAll, describe, expect, it } from 'vitest';
import { compileCopy, CopyError, emitCatalog, emitSwift, emitTypeScript, GENERATED_HEADER, parseMessage, analyze, type Node } from './copy.ts';
import { check, copyOutputs, generate, loadSources, outputs, REPOSITORY_ROOT } from './generate.ts';
import { compilePreferences, emitPreferencesSwift, emitPreferencesTypeScript, PreferenceError } from './preferences.ts';
import { compileTokens, emitTokensCss, emitTokensSwift, emitTokensTypeScript, TokenError } from './tokens.ts';

const scratchFolders: string[] = [];
afterAll(() => {
  for (const folder of scratchFolders) rmSync(folder, { recursive: true, force: true });
});
function scratch(): string {
  const folder = mkdtempSync(join(tmpdir(), 'carrier-design-test-'));
  scratchFolders.push(folder);
  return folder;
}

/** One message through the parser and the analysis, the way the generator reads each key. */
function read(message: string) {
  return analyze('key', 'en', parseMessage('key', 'en', message));
}

describe('the ICU subset', () => {
  const accepted: Record<string, string> = {
    'plain text': 'Hello',
    'a string argument': 'Hello {name}',
    'a number': '{count, number} items',
    'a plural with =0, categories and #': '{count, plural, =0 {none} one {# item} two {a pair} few {# few} many {# many} other {# items}}',
    'a select': '{kind, select, a {A} b {B} other {C}}',
    'a plural inside a select': '{kind, select, a {{count, plural, one {# a} other {# as}}} other {x}}',
    'a select inside a plural': '{count, plural, one {{kind, select, a {# a} other {# b}}} other {# c}}',
    'a plural inside a plural': '{a, plural, one {{b, plural, one {x} other {y}}} other {z}}',
    'a # outside a plural is text': 'Issue #12',
    'an apostrophe inside a word is text': "Carrier's own tools, {name}'s too",
  };
  for (const [name, message] of Object.entries(accepted)) {
    it(`accepts ${name}`, () => {
      expect(() => read(message)).not.toThrow();
    });
  }

  const refused: Record<string, [string, string]> = {
    selectordinal: ['{n, selectordinal, one {#st} other {#th}}', 'selectordinal is not supported'],
    date: ['{when, date}', 'date is not supported'],
    time: ['{when, time}', 'time is not supported'],
    'a number style': ['{n, number, percent}', 'number styles are not supported'],
    'an =N other than =0': ['{n, plural, =1 {one} other {many}}', '"=1" is not supported'],
    offset: ['{n, plural, offset:1 one {a} other {b}}', 'plural offset is not supported'],
    'zero as a category': ['{n, plural, zero {none} other {some}}', 'use =0'],
    'an unknown category': ['{n, plural, several {x} other {y}}', 'unknown plural category'],
    'an apostrophe that quotes a brace': ["It's '{here}", 'apostrophe quoting is not supported'],
    'an escaped apostrophe': ["It''s here", 'apostrophe quoting is not supported'],
    'nesting deeper than one level': [
      '{a, select, x {{b, plural, one {{c, plural, one {1} other {2}}} other {3}}} other {4}}',
      'nesting deeper than one level',
    ],
    'more than one select': ['{a, select, x {X} other {Y}} {b, select, x {X} other {Y}}', 'more than one select'],
    'a plural without other': ['{n, plural, one {# item}}', 'plural without "other"'],
    'an unknown type': ['{n, spellout}', 'unknown argument type "spellout"'],
    'an unbalanced brace': ['{n', 'expected'],
    'a closing brace alone': ['a } b', 'unbalanced'],
    'an argument used as two kinds': ['{n} {n, number}', 'argument "n" is used as string and as number'],
  };
  for (const [name, [message, reason]] of Object.entries(refused)) {
    it(`refuses ${name}, naming the key`, () => {
      expect(() => read(message)).toThrow(CopyError);
      expect(() => read(message)).toThrow(`copy key "key" (en)`);
      expect(() => read(message)).toThrow(reason);
    });
  }
});

describe('English is the source', () => {
  const compile = (en: Record<string, string>, es: Record<string, string>) => compileCopy({ en, es });

  it('accepts the same arguments in both languages, in any order', () => {
    expect(() => compile({ greet: 'Hello {name}, {count, number}' }, { greet: '{count, number}: hola {name}' })).not.toThrow();
  });

  it('fails a key missing in Spanish, naming it', () => {
    expect(() => compile({ a: 'A', b: 'B' }, { a: 'A' })).toThrow('copy key "b" is missing in es');
  });

  it('fails a key Spanish has and English lacks', () => {
    expect(() => compile({ a: 'A' }, { a: 'A', b: 'B' })).toThrow('copy key "b" is in es and not in en');
  });

  it('fails arguments that differ from English', () => {
    expect(() => compile({ greet: 'Hello {name}' }, { greet: 'Hola {nombre}' })).toThrow('copy key "greet" (es): arguments');
    expect(() => compile({ n: '{count, number}' }, { n: '{count}' })).toThrow('copy key "n" (es): arguments');
  });

  it('fails select branches that use different arguments in two languages', () => {
    const en = { k: '{kind, select, a {{x}} other {{y}}}' };
    expect(() => compile(en, { k: '{kind, select, a {{y}} other {{x}}}' })).toThrow('copy key "k" (es): select branches');
  });

  it('fails select branches that are not the same in two languages', () => {
    expect(() => compile({ k: '{kind, select, a {A} other {O}}' }, { k: '{kind, select, b {B} other {O}}' })).toThrow('select branches');
  });

  it('fails a key that is not lowerCamelCase', () => {
    expect(() => compile({ 'a.b': 'A' }, { 'a.b': 'A' })).toThrow('copy key "a.b" is not lowerCamelCase');
  });

  it('accepts text.<code> for the words of a text code and fails one that is not', () => {
    expect(() => compile({ 'text.session.busy': 'A' }, { 'text.session.busy': 'B' })).not.toThrow();
    for (const key of ['text.busy', 'text.Session.busy', 'text.session.busy2', 'text.session..busy']) {
      expect(() => compile({ [key]: 'A' }, { [key]: 'B' })).toThrow(`copy key "${key}" is not text.<code>`);
    }
  });
});

const small = compileCopy({
  en: {
    greeting: 'Hello {name}',
    epicsWaiting: '{count, plural, =0 {No epics waiting} one {# epic waiting} other {# epics waiting}}',
    epicState: '{state, select, running {{count, plural, one {# epic running} other {# epics running}}} other {Stopped}}',
  },
  es: {
    greeting: 'Hola {name}',
    epicsWaiting: '{count, plural, =0 {Ningún epic en espera} one {# epic en espera} other {# epics en espera}}',
    epicState: '{state, select, running {{count, plural, one {# epic en marcha} other {# epics en marcha}}} other {Detenido}}',
  },
});

describe('the Swift accessor', () => {
  it('starts with the generated line and reads carrierResources', () => {
    const swift = emitSwift(small);
    expect(swift.split('\n')[0]).toBe(GENERATED_HEADER);
    expect(swift).not.toContain('Bundle.module');
  });

  it('is a typed function per key', () => {
    expect(emitSwift(small)).toMatchInlineSnapshot(`
      "// Generated by design/generate.ts from design/; do not edit.

      import Foundation

      public enum Copy {
          /// One language's catalog, for tests; the app passes none and gets the language macOS gives it.
          public static func bundle(_ language: String) -> Bundle {
              carrierResources.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? carrierResources
          }

          public static func greeting(name: String, bundle: Bundle? = nil, locale: Locale = .current) -> String {
              String(localized: "greeting \\(name)", bundle: bundle ?? carrierResources, locale: locale)
          }

          public static func epicsWaiting(count: Int, bundle: Bundle? = nil, locale: Locale = .current) -> String {
              String(localized: "epicsWaiting \\(count)", bundle: bundle ?? carrierResources, locale: locale)
          }

          public enum EpicState: Sendable { case running; case other }
          public static func epicState(state: EpicState, count: Int, bundle: Bundle? = nil, locale: Locale = .current) -> String {
              switch state {
              case .running: return String(localized: "epicState.running \\(count)", bundle: bundle ?? carrierResources, locale: locale)
              case .other: return String(localized: "epicState.other", bundle: bundle ?? carrierResources, locale: locale)
              }
          }
      }
      "
    `);
  });
});

describe('the catalog', () => {
  it('holds a plural as a substitution, =0 as zero, each select branch as its own key, with positional specifiers', () => {
    expect(emitCatalog(small)).toMatchInlineSnapshot(`
      "{
        "sourceLanguage": "en",
        "strings": {
          "epicState.other": {
            "extractionState": "manual",
            "localizations": {
              "en": {
                "stringUnit": {
                  "state": "translated",
                  "value": "Stopped"
                }
              },
              "es": {
                "stringUnit": {
                  "state": "translated",
                  "value": "Detenido"
                }
              }
            }
          },
          "epicState.running %lld": {
            "extractionState": "manual",
            "localizations": {
              "en": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%#@count@"
                },
                "substitutions": {
                  "count": {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                      "plural": {
                        "one": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "%arg epic running"
                          }
                        },
                        "other": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "%arg epics running"
                          }
                        }
                      }
                    }
                  }
                }
              },
              "es": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%#@count@"
                },
                "substitutions": {
                  "count": {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                      "plural": {
                        "one": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "%arg epic en marcha"
                          }
                        },
                        "other": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "%arg epics en marcha"
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          },
          "epicsWaiting %lld": {
            "extractionState": "manual",
            "localizations": {
              "en": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%#@count@"
                },
                "substitutions": {
                  "count": {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                      "plural": {
                        "zero": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "No epics waiting"
                          }
                        },
                        "one": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "%arg epic waiting"
                          }
                        },
                        "other": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "%arg epics waiting"
                          }
                        }
                      }
                    }
                  }
                }
              },
              "es": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%#@count@"
                },
                "substitutions": {
                  "count": {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                      "plural": {
                        "zero": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "Ningún epic en espera"
                          }
                        },
                        "one": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "%arg epic en espera"
                          }
                        },
                        "other": {
                          "stringUnit": {
                            "state": "translated",
                            "value": "%arg epics en espera"
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          },
          "greeting %@": {
            "extractionState": "manual",
            "localizations": {
              "en": {
                "stringUnit": {
                  "state": "translated",
                  "value": "Hello %1$@"
                }
              },
              "es": {
                "stringUnit": {
                  "state": "translated",
                  "value": "Hola %1$@"
                }
              }
            }
          }
        },
        "version": "1.0"
      }
      "
    `);
  });
});

describe('the TypeScript', () => {
  it('is a function per key', () => {
    expect(emitTypeScript(small)).toMatchInlineSnapshot(`
      "// Generated by design/generate.ts from design/; do not edit.

      export type Language = 'en' | 'es';

      const languages: readonly string[] = ['en', 'es'];

      /** The language of a locale such as "es-AR"; a language with no words here reads as en. */
      function languageOf(locale: string): Language {
        const language = locale.split(/[-_]/)[0] ?? '';
        return (languages.includes(language) ? language : 'en') as Language;
      }

      function formatNumber(locale: string, value: number): string {
        return new Intl.NumberFormat(locale).format(value);
      }

      function pluralOf(locale: string, value: number, cases: { other: string; [selector: string]: string }): string {
        const exact = value === 0 ? cases['=0'] : undefined;
        return exact ?? cases[new Intl.PluralRules(locale).select(value)] ?? cases.other;
      }

      export function greeting(locale: string, args: { name: string }): string {
        switch (languageOf(locale)) {
          case 'en': return "Hello " + args.name;
          case 'es': return "Hola " + args.name;
        }
      }

      export function epicsWaiting(locale: string, args: { count: number }): string {
        switch (languageOf(locale)) {
          case 'en': return pluralOf(locale, args.count, { "=0": "No epics waiting", "one": formatNumber(locale, args.count) + " epic waiting", "other": formatNumber(locale, args.count) + " epics waiting" });
          case 'es': return pluralOf(locale, args.count, { "=0": "Ningún epic en espera", "one": formatNumber(locale, args.count) + " epic en espera", "other": formatNumber(locale, args.count) + " epics en espera" });
        }
      }

      export function epicState(locale: string, args: { state: 'running' | 'other'; count: number }): string {
        switch (languageOf(locale)) {
          case 'en': return ({ "running": pluralOf(locale, args.count, { "one": formatNumber(locale, args.count) + " epic running", "other": formatNumber(locale, args.count) + " epics running" }), "other": "Stopped" })[args.state];
          case 'es': return ({ "running": pluralOf(locale, args.count, { "one": formatNumber(locale, args.count) + " epic en marcha", "other": formatNumber(locale, args.count) + " epics en marcha" }), "other": "Detenido" })[args.state];
        }
      }
      "
    `);
  });
});

const smallTokens = compileTokens({
  theme: {
    carrier: { light: { window: '#f2f2f7', sidebar: '#dcdce2', accent: null }, dark: { window: '#1c1c1e', sidebar: '#2f2f33', accent: null } },
    ocean: { light: { window: '#eaf3fa', sidebar: '#cfe3f2', accent: '#0a7fc0' }, dark: { window: '#0f1b24', sidebar: '#18304a', accent: '#32ade6' } },
  },
  accent: { blue: '#0a84ff', orange: '#ff9f0a' },
  radius: { chip: 6 },
  space: { rowGap: 8 },
  duration: { fast: 0.15 },
  semantic: {
    status: { attention: { light: '#b35c00', dark: '{accent.orange}' }, slowCall: '{semantic.status.attention}' },
    accent: { glass: { darken: 0.4 }, selectedRow: { light: { alpha: 0.45 }, dark: { darken: 0.5, alpha: 0.85 } } },
  },
});

describe('the tokens', () => {
  it('are Swift constants', () => {
    expect(emitTokensSwift(smallTokens)).toMatchInlineSnapshot(`
      "// Generated by design/generate.ts from design/; do not edit.

      /// One value for each of the two versions the color scheme picks between.
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

      public enum Tokens {
          /// The themes by name, each in light and dark.
          public static let themes: [String: SchemePair<ThemeColors>] = [
              "carrier": SchemePair(light: ThemeColors(window: 0xf2f2f7, sidebar: 0xdcdce2, accent: nil), dark: ThemeColors(window: 0x1c1c1e, sidebar: 0x2f2f33, accent: nil)),
              "ocean": SchemePair(light: ThemeColors(window: 0xeaf3fa, sidebar: 0xcfe3f2, accent: 0x0a7fc0), dark: ThemeColors(window: 0x0f1b24, sidebar: 0x18304a, accent: 0x32ade6)),
          ]

          /// The accent presets, in the order the picker shows them.
          public static let accents: [(name: String, hex: UInt32)] = [
              ("blue", 0x0a84ff),
              ("orange", 0xff9f0a),
          ]

          public enum Radius {
              public static let chip: Double = 6
          }

          public enum Space {
              public static let rowGap: Double = 8
          }

          public enum Duration {
              public static let fast: Double = 0.15
          }

          public enum Status {
              public static let attention = SchemePair<UInt32>(light: 0xb35c00, dark: 0xff9f0a)
              public static let slowCall = SchemePair<UInt32>(light: 0xb35c00, dark: 0xff9f0a)
          }

          public enum Accent {
              public static let glass = SchemePair<AccentShade>(light: AccentShade(darken: 0.4, alpha: 1), dark: AccentShade(darken: 0.4, alpha: 1))
              public static let selectedRow = SchemePair<AccentShade>(light: AccentShade(darken: 0, alpha: 0.45), dark: AccentShade(darken: 0.5, alpha: 0.85))
          }
      }
      "
    `);
  });

  it('are TypeScript values', () => {
    expect(emitTokensTypeScript(smallTokens)).toMatchInlineSnapshot(`
      "// Generated by design/generate.ts from design/; do not edit.

      export interface ThemeColors { window: string; sidebar: string; accent: string | null }

      export interface Shade { darken: number; alpha: number }

      export const themes = {
        carrier: { light: { window: '#f2f2f7', sidebar: '#dcdce2', accent: null }, dark: { window: '#1c1c1e', sidebar: '#2f2f33', accent: null } },
        ocean: { light: { window: '#eaf3fa', sidebar: '#cfe3f2', accent: '#0a7fc0' }, dark: { window: '#0f1b24', sidebar: '#18304a', accent: '#32ade6' } },
      } as const;

      export const accents = {
        blue: '#0a84ff',
        orange: '#ff9f0a',
      } as const;

      export const radius = {
        chip: 6,
      } as const;

      export const space = {
        rowGap: 8,
      } as const;

      export const duration = {
        fast: 0.15,
      } as const;

      export const semantic = {
        status: {
          attention: { light: '#b35c00', dark: '#ff9f0a' },
          slowCall: { light: '#b35c00', dark: '#ff9f0a' },
        },
        accent: {
          glass: { light: { darken: 0.4, alpha: 1 }, dark: { darken: 0.4, alpha: 1 } },
          selectedRow: { light: { darken: 0, alpha: 0.45 }, dark: { darken: 0.5, alpha: 0.85 } },
        },
      } as const;
      "
    `);
  });

  it('are CSS variables', () => {
    expect(emitTokensCss(smallTokens)).toMatchInlineSnapshot(`
      "/* Generated by design/generate.ts from design/; do not edit. */

      :root {
        --accent-blue: #0a84ff;
        --accent-orange: #ff9f0a;
        --radius-chip: 6px;
        --space-row-gap: 8px;
        --duration-fast: 0.15s;
        --status-attention: #b35c00;
        --status-slow-call: #b35c00;
        --accent-glass: color-mix(in srgb, var(--accent) 60%, black);
        --accent-selected-row: color-mix(in srgb, var(--accent) 45%, transparent);
      }

      [data-scheme='dark'] {
        --status-attention: #ff9f0a;
        --status-slow-call: #ff9f0a;
        --accent-selected-row: color-mix(in srgb, color-mix(in srgb, var(--accent) 50%, black) 85%, transparent);
      }

      [data-theme='carrier'] {
        --window: #f2f2f7;
        --sidebar: #dcdce2;
      }

      [data-theme='carrier'][data-scheme='dark'] {
        --window: #1c1c1e;
        --sidebar: #2f2f33;
      }

      [data-theme='ocean'] {
        --window: #eaf3fa;
        --sidebar: #cfe3f2;
        --accent: #0a7fc0;
      }

      [data-theme='ocean'][data-scheme='dark'] {
        --window: #0f1b24;
        --sidebar: #18304a;
        --accent: #32ade6;
      }
      "
    `);
  });

  it('refuse what the layers do not allow, naming the token', () => {
    const base = { theme: {}, accent: { blue: '#0a84ff' } };
    const refuse = (source: unknown, message: string) => expect(() => compileTokens(source)).toThrow(new RegExp(message));
    refuse({ ...base, accent: { blue: '0a84ff' } }, 'accent.blue is not a #rrggbb hex');
    refuse({ ...base, semantic: { status: { done: '{accent.red}' } } }, 'semantic.status.done: "{accent.red}" points at nothing');
    refuse({ ...base, semantic: { status: { done: '{semantic.status.done}' } } }, 'refers back to itself');
    refuse({ ...base, semantic: { status: { done: { light: '#000000' } } } }, 'semantic.status.done is neither');
    refuse({ ...base, semantic: { status: { done: { light: '#000000', dark: { darken: 0.1 } } } } }, 'both be colours or both be shades');
    refuse({ ...base, colour: {} }, 'unknown section "colour"');
    expect(() => compileTokens({ ...base, accent: { Blue: '#0a84ff' } })).toThrow(TokenError);
  });

  it('are in the output table with the Swift written and the TypeScript and CSS written nowhere', () => {
    expect(outputs.map((output) => output.path)).toEqual([
      'macos/Sources/CarrierCore/Theme/Tokens.generated.swift',
      'macos/Sources/CarrierCore/Settings/Preferences.generated.swift',
      'macos/Sources/CarrierCore/Copy/Copy.generated.swift',
      'macos/Sources/CarrierCore/Resources/Localizable.xcstrings',
    ]);
  });

  it('commit the nine themes and the seven accent presets', () => {
    const { themes, accents } = loadSources(REPOSITORY_ROOT).tokens;
    expect(themes.map(([name]) => name)).toEqual(['carrier', 'graphite', 'ocean', 'forest', 'sunset', 'paper', 'rose', 'lavender', 'midnight']);
    expect(accents.map(([name]) => name)).toEqual(['blue', 'purple', 'pink', 'red', 'orange', 'green', 'graphite']);
  });
});

const smallPreferences = {
  'menu.animate': { type: 'bool', default: true, page: 'general' },
  'appearance.density': { values: ['compact', 'comfortable'], swift: 'Density', default: 'comfortable', page: 'appearance' },
  'terminal.font.size': { type: 'double', optional: true, page: 'terminal' },
  'sidebar.width': { type: 'double', default: 360, page: 'sidebar' },
  'dictation.sound.start': { values: ['Tink', 'Pop'], default: 'Tink', page: 'dictation' },
  'sessions.seen': { type: 'map', of: 'double', default: {}, page: 'none' },
};

describe('the preferences', () => {
  it('are Swift keys and the per-page reset', () => {
    expect(emitPreferencesSwift(compilePreferences(smallPreferences))).toMatchInlineSnapshot(`
      "// Generated by design/generate.ts from design/; do not edit.

      import Foundation

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

      extension Density: PreferenceValue {}

      public enum Preference {
          public static let menuAnimate = PreferenceKey<Bool>("menu.animate", default: true)
          public static let appearanceDensity = PreferenceKey<Density>("appearance.density", default: Density(rawValue: "comfortable")!)
          public static let terminalFontSize = OptionalPreferenceKey<Double>("terminal.font.size")
          public static let sidebarWidth = PreferenceKey<Double>("sidebar.width", default: 360)
          public static let dictationSoundStart = PreferenceKey<String>("dictation.sound.start", default: "Tink")
          public static let sessionsSeen = PreferenceKey<[String: Double]>("sessions.seen", default: [:])

          /// The names each page's Reset takes out of user defaults, so the page reads as its defaults again.
          public static let resetNames: [SettingsPage: [String]] = [
              .general: [menuAnimate.name],
              .appearance: [appearanceDensity.name],
              .dictation: [dictationSoundStart.name],
              .sidebar: [sidebarWidth.name],
              .terminal: [terminalFontSize.name],
          ]

          /// Takes the preferences of one page out, and no other.
          public static func reset(_ page: SettingsPage, in defaults: UserDefaults = .standard) {
              for name in resetNames[page] ?? [] { defaults.removeObject(forKey: name) }
          }
      }
      "
    `);
  });

  it('are TypeScript declarations', () => {
    expect(emitPreferencesTypeScript(compilePreferences(smallPreferences))).toMatchInlineSnapshot(`
      "// Generated by design/generate.ts from design/; do not edit.

      /** What each preference holds; an optional one is absent until it is set. */
      export interface Preferences {
        "menu.animate": boolean;
        "appearance.density": "compact" | "comfortable";
        "terminal.font.size"?: number;
        "sidebar.width": number;
        "dictation.sound.start": "Tink" | "Pop";
        "sessions.seen": Record<string, number>;
      }

      /** What each preference reads as while none is saved. */
      export const preferenceDefaults = {
        "menu.animate": true,
        "appearance.density": "comfortable",
        "sidebar.width": 360,
        "dictation.sound.start": "Tink",
        "sessions.seen": {},
      } as const;

      /** The Settings page whose Reset clears each preference; 'none' when no page does. */
      export const preferencePages = {
        "menu.animate": 'general',
        "appearance.density": 'appearance',
        "terminal.font.size": 'terminal',
        "sidebar.width": 'sidebar',
        "dictation.sound.start": 'dictation',
        "sessions.seen": 'none',
      } as const;
      "
    `);
  });

  const refused: Record<string, [Record<string, unknown>, string]> = {
    'an unknown type': [{ a: { type: 'float', default: 1, page: 'general' } }, 'preference "a": unknown type "float"'],
    'a default of the wrong type': [{ a: { type: 'int', default: 'x', page: 'general' } }, 'preference "a": default "x" is not a int'],
    'a default outside the enum': [{ a: { values: ['one', 'two'], default: 'three', page: 'general' } }, 'preference "a": default "three" is not one of one, two'],
    'a key with no page': [{ a: { type: 'bool', default: true } }, 'preference "a": has no Settings page'],
    'a key with a page that does not exist': [{ a: { type: 'bool', default: true, page: 'nowhere' } }, 'preference "a": has no Settings page'],
    'a key with no default': [{ a: { type: 'bool', page: 'general' } }, 'preference "a": has no default'],
    'an optional key with a default': [{ a: { type: 'bool', optional: true, default: true, page: 'general' } }, 'preference "a": is optional, so it has no default'],
    'two keys with the same Swift name': [{ 'a.b': { type: 'bool', default: true, page: 'general' }, aB: { type: 'bool', default: true, page: 'general' } }, 'makes the Swift name "aB" again'],
  };
  for (const [name, [source, message]] of Object.entries(refused)) {
    it(`refuses ${name}, naming the key`, () => {
      expect(() => compilePreferences(source)).toThrow(PreferenceError);
      expect(() => compilePreferences(source)).toThrow(message);
    });
  }

  it('are in the output table with the Swift written and the TypeScript written nowhere', () => {
    expect(outputs.map((output) => output.path)).toContain('macos/Sources/CarrierCore/Settings/Preferences.generated.swift');
  });
});

describe('the output table and the check', () => {
  const paths = { swift: 'out/Copy.generated.swift', catalog: 'out/Localizable.xcstrings', typescript: 'out/copy.ts' };
  const table = copyOutputs(paths);

  function tree(): string {
    const root = scratch();
    mkdirSync(join(root, 'design', 'copy'), { recursive: true });
    for (const language of ['en', 'es']) writeFileSync(join(root, 'design', 'copy', `${language}.json`), readFileSync(join(REPOSITORY_ROOT, 'design', 'copy', `${language}.json`)));
    for (const source of ['tokens.json', 'preferences.json']) writeFileSync(join(root, 'design', source), readFileSync(join(REPOSITORY_ROOT, 'design', source)));
    return root;
  }

  it('finds nothing to report on a tree the generator just wrote', () => {
    const root = tree();
    generate(root, table);
    expect(check(root, table)).toEqual([]);
  });

  it('names each file that differs or is missing', () => {
    const root = tree();
    generate(root, table);
    writeFileSync(join(root, paths.swift), '// edited by hand\n');
    rmSync(join(root, paths.catalog));
    expect(check(root, table)).toEqual([`${paths.swift}: differs`, `${paths.catalog}: missing`]);
  });

  it('names a file that was never generated', () => {
    expect(check(tree(), table)).toEqual(table.map((output) => `${output.path}: missing`));
  });

  it('does not write into the tree it checks', () => {
    const root = tree();
    check(root, table);
    expect(() => readFileSync(join(root, paths.swift))).toThrow();
  });

  it('fails the run on a source the subset refuses', () => {
    const root = tree();
    writeFileSync(join(root, 'design', 'copy', 'es.json'), '{}');
    expect(() => check(root, table)).toThrow(CopyError);
  });
});

describe('the committed copy', () => {
  it('compiles', () => {
    expect(loadSources(REPOSITORY_ROOT).copy.keys.length).toBeGreaterThan(0);
  });

  it('says the same in TypeScript as the shared fixtures', async () => {
    const folder = scratch();
    writeFileSync(join(folder, 'copy.ts'), emitTypeScript(loadSources(REPOSITORY_ROOT).copy));
    const copy = (await import(/* @vite-ignore */ pathToFileURL(join(folder, 'copy.ts')).href)) as Record<string, (locale: string, args?: unknown) => string>;
    const fixtures = JSON.parse(readFileSync(join(REPOSITORY_ROOT, 'design', 'copy', 'fixtures.json'), 'utf8')) as {
      key: string;
      args: Record<string, unknown>;
      language: string;
      region: string;
      text: string;
    }[];
    const locales = new Set(fixtures.map((fixture) => `${fixture.language}-${fixture.region}`));
    expect([...locales].sort()).toEqual(['en-US', 'es-AR', 'es-ES']);
    for (const fixture of fixtures) {
      const render = copy[fixture.key];
      expect(render, `copy key "${fixture.key}"`).toBeTypeOf('function');
      const locale = `${fixture.language}-${fixture.region}`;
      const text = Object.keys(fixture.args).length === 0 ? render!(locale) : render!(locale, fixture.args);
      expect(text, `${fixture.key} in ${locale}`).toBe(fixture.text);
    }
  });
});

describe('the words of the text codes', () => {
  type Golden = Record<string, { params: Record<string, string | number> }>;
  const golden = JSON.parse(readFileSync(join(REPOSITORY_ROOT, 'macos', 'Tests', 'Fixtures', 'text-codes.json'), 'utf8')) as Golden;
  const sources = Object.fromEntries(['en', 'es'].map((language) => [language, JSON.parse(readFileSync(join(REPOSITORY_ROOT, 'design', 'copy', `${language}.json`), 'utf8')) as Record<string, string>]));
  const copy = loadSources(REPOSITORY_ROOT).copy;
  const keys = new Map(copy.keys.map((compiled) => [compiled.key, compiled]));

  // A param whose words are in the sentence already, or that is the code of another text, is not an argument of the key.
  // Each one is here on purpose: a param that is missing from a key and not named here fails.
  const unused: Record<string, string[]> = {
    'account.harnessTakesOne': ['harness'],
    'doctor.labelsMissing': ['count'],
    'epic.stop.usageLimitWakeRefused': ['ranOut'],
    'session.notice.actionWentOn': ['reasonCode'],
    'session.notice.projectNotAdded': ['reasonCode'],
    'session.notice.startedFromFetched': ['reasonCode'],
    'session.notice.startedFromLocal': ['reasonCode'],
  };

  const plurals = (nodes: Node[]): { name: string; selectors: string[] }[] =>
    nodes.flatMap((node) => {
      if (node.type === 'plural') return [{ name: node.name, selectors: node.cases.map((branch) => branch.selector) }, ...node.cases.flatMap((branch) => plurals(branch.nodes))];
      if (node.type === 'select') return node.cases.flatMap((branch) => plurals(branch.nodes));
      return [];
    });

  it('has text.<code> in English and in Spanish for every code of text-codes.json', () => {
    expect(Object.keys(golden).length).toBeGreaterThan(100);
    for (const code of Object.keys(golden)) {
      for (const language of ['en', 'es']) expect(sources[language]![`text.${code}`], `text.${code} in ${language}`).toBeTypeOf('string');
    }
  });

  it('takes as arguments the params of the code, none that it does not carry', () => {
    for (const [code, { params }] of Object.entries(golden)) {
      const args = [...(keys.get(`text.${code}`)?.analysis.args.keys() ?? [])].sort();
      const left = unused[code] ?? [];
      expect(args, `text.${code}`).toEqual(Object.keys(params).filter((name) => !left.includes(name)).sort());
    }
    for (const [code, left] of Object.entries(unused)) expect(Object.keys(golden[code]!.params), code).toEqual(expect.arrayContaining(left));
  });

  it('types the arguments as the example of the params does: a number where the example is one, a branch where the key selects', () => {
    for (const [code, { params }] of Object.entries(golden)) {
      const { analysis } = keys.get(`text.${code}`)!;
      for (const [name, value] of Object.entries(params)) {
        const kind = analysis.args.get(name);
        if (kind === undefined) continue;
        expect(kind === 'number', `text.${code} ${name}`).toBe(typeof value === 'number');
        if (kind === 'select') expect([...analysis.branches.keys()], `text.${code} ${name}`).toContain(value);
      }
    }
  });

  it('has the plural forms of both languages for each plural', () => {
    let count = 0;
    for (const compiled of copy.keys.filter((candidate) => candidate.key.startsWith('text.'))) {
      for (const language of ['en', 'es'] as const) {
        for (const { name, selectors } of plurals(compiled.messages[language])) {
          // `{idle, plural, =0 {} other {...}}` says a clause or none, it is not a count of things
          if (selectors.length === 2 && selectors.includes('=0')) continue;
          count++;
          expect(selectors, `${compiled.key} ${name} in ${language}`).toEqual(expect.arrayContaining(['one', 'other']));
        }
      }
    }
    expect(count).toBeGreaterThan(10);
  });

  it('holds a plural of a code in the generated catalog, with the forms of both languages', () => {
    const catalog = JSON.parse(emitCatalog(copy)) as { strings: Record<string, { localizations: Record<string, { stringUnit: { value: string }; substitutions?: Record<string, { variations: { plural: Record<string, { stringUnit: { value: string } }> } }> }> }> };
    const entry = catalog.strings['text.workspace.dirty %lld %@']!;
    const forms = (language: string) => Object.fromEntries(Object.entries(Object.values(entry.localizations[language]!.substitutions!)[0]!.variations.plural).map(([form, unit]) => [form, unit.stringUnit.value]));
    expect(forms('en')).toEqual({ one: '%arg uncommitted file', other: '%arg uncommitted files' });
    expect(forms('es')).toEqual({ one: '%arg archivo sin confirmar', other: '%arg archivos sin confirmar' });
    expect(entry.localizations.en!.stringUnit.value).toBe('The folder has %#@count@, so its branch was not changed to %2$@. Save the work and try again.');
  });

  it('has no function in the Swift or the TypeScript, which find the words by the code they receive', () => {
    expect(emitSwift(copy)).not.toContain('text.');
    expect(emitTypeScript(copy)).not.toContain('text.');
  });
});
