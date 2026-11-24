import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { afterAll, describe, expect, it } from 'vitest';
import { compileCopy, CopyError, emitCatalog, emitSwift, emitTypeScript, GENERATED_HEADER, parseMessage, analyze } from './copy.ts';
import { check, copyOutputs, generate, loadSources, REPOSITORY_ROOT } from './generate.ts';

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
    'apostrophe quoting': ["It's here", 'apostrophe quoting is not supported'],
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

describe('the output table and the check', () => {
  const paths = { swift: 'out/Copy.generated.swift', catalog: 'out/Localizable.xcstrings', typescript: 'out/copy.ts' };
  const table = copyOutputs(paths);

  function tree(): string {
    const root = scratch();
    mkdirSync(join(root, 'design', 'copy'), { recursive: true });
    for (const language of ['en', 'es']) writeFileSync(join(root, 'design', 'copy', `${language}.json`), readFileSync(join(REPOSITORY_ROOT, 'design', 'copy', `${language}.json`)));
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
