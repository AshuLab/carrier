/**
 * Whether a shell command of the agent is one of the `gh` commands that change an epic's slices (take, open, merge, close).
 * Only a signal to look: the data still comes from GitHub, so a missed or false match costs one query or one timer period.
 */
export const changesSlices = (command: string) =>
  /(^|[\s;&|(])gh\s+(?:issue\s+(?:edit|close)|pr\s+(?:create|merge|ready|close))(?=\s|$)/.test(command);
