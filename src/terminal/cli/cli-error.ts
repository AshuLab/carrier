import type { ConfigError } from '../../config/load.ts';

/** A failure to report to the person at the terminal and exit with `code`: bad usage (2) or a problem they can fix (1). */
export class CliError extends Error {
  readonly code: number;
  readonly lines: string[];

  // No parameter properties: Node strips types at runtime and cannot run that syntax.
  constructor(code: number, ...lines: string[]) {
    super(lines.join('\n'));
    this.code = code;
    this.lines = lines;
  }
}

/** `engine.json` refused by its schema: the lines a start prints, and the problems they were made from, so a reload can name the key and the kind. */
export class InvalidConfig extends CliError {
  readonly errors: ConfigError[];

  constructor(errors: ConfigError[], ...lines: string[]) {
    super(1, ...lines);
    this.errors = errors;
  }
}
