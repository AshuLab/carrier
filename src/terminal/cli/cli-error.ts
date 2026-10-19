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
