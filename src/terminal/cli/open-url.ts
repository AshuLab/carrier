import { spawn } from 'node:child_process';

// Only GitHub issue and PR pages, whatever the row says: the URL goes to `open`, which would take anything.
const githubPage = /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/(issues|pull)\/\d+$/;
/** Opens a GitHub issue or PR page in the browser. */
export function openUrl(url: string) {
  if (!githubPage.test(url)) return;
  spawn('open', [url], { stdio: 'ignore', detached: true }).on('error', () => {}).unref(); // macOS; where `open` is missing nothing happens
}
