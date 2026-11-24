// Writes the code of each front-end from the sources in design/ (ADR 0054, spec section 7).
//   node design/generate.ts            writes the generated files
//   node design/generate.ts --check    writes them to a temporary folder and fails when a committed one differs or is missing
// No dependency: Node runs this file as it is.

import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { type CompiledCopy, CopyError, LANGUAGES, type Language, compileCopy, emitCatalog, emitSwift, emitTypeScript } from './copy.ts';

export interface Sources {
  copy: CompiledCopy;
}

/** A file the generator writes: its path from the repository root, and what it holds. */
export interface Output {
  path: string;
  render: (sources: Sources) => string;
}

/** The copy emitter's three files, where the caller puts them. */
export function copyOutputs(paths: { swift: string; catalog: string; typescript: string }): Output[] {
  return [
    { path: paths.swift, render: (sources) => emitSwift(sources.copy) },
    { path: paths.catalog, render: (sources) => emitCatalog(sources.copy) },
    { path: paths.typescript, render: (sources) => emitTypeScript(sources.copy) },
  ];
}

/**
 * The output table: every emitter registers the files it writes here.
 * It is empty on purpose.
 * The Swift outputs (the copy accessor and catalog, the tokens, the preferences) arrive with the changes that use them,
 * and the web's TypeScript with the web; the copy source is still parsed and checked on every run.
 */
export const outputs: Output[] = [];

export const REPOSITORY_ROOT = join(import.meta.dirname, '..');

export function loadSources(root: string): Sources {
  const read = (language: Language): Record<string, string> => {
    const file = join(root, 'design', 'copy', `${language}.json`);
    const parsed: unknown = JSON.parse(readFileSync(file, 'utf8'));
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) throw new CopyError(`${file} is not an object of copy keys`);
    for (const [key, value] of Object.entries(parsed)) {
      if (typeof value !== 'string') throw new CopyError(`copy key "${key}" (${language}) is not a string`);
    }
    return parsed as Record<string, string>;
  };
  const [en, es] = LANGUAGES.map(read) as [Record<string, string>, Record<string, string>];
  return { copy: compileCopy({ en, es }) };
}

function write(folder: string, table: Output[], sources: Sources): void {
  for (const output of table) {
    const file = join(folder, output.path);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, output.render(sources));
  }
}

export function generate(root: string, table: Output[] = outputs): void {
  write(root, table, loadSources(root));
}

/** The files whose committed text is not what the generator makes: one line each, naming the file. */
export function check(root: string, table: Output[] = outputs): string[] {
  const scratch = mkdtempSync(join(tmpdir(), 'carrier-design-'));
  try {
    write(scratch, table, loadSources(root));
    const problems: string[] = [];
    for (const output of table) {
      const committed = join(root, output.path);
      if (!existsSync(committed)) problems.push(`${output.path}: missing`);
      else if (readFileSync(committed, 'utf8') !== readFileSync(join(scratch, output.path), 'utf8')) problems.push(`${output.path}: differs`);
    }
    return problems;
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

function main(): number {
  try {
    if (process.argv.includes('--check')) {
      const problems = check(REPOSITORY_ROOT);
      if (problems.length === 0) return 0;
      for (const problem of problems) console.error(problem);
      console.error('The generated files are out of date: run `pnpm design` and commit the result.');
      return 1;
    }
    generate(REPOSITORY_ROOT);
    return 0;
  } catch (error) {
    if (error instanceof CopyError) {
      console.error(error.message);
      return 1;
    }
    throw error;
  }
}

if (import.meta.main) process.exitCode = main();
