/** What GitHub may have changed for a session's row, by the commands its agent ran: only these are worth a request. */
export type GithubWork = {
  /** The branch or its pull request may be another now: look for the pull request of the branch checked out. */
  find: boolean;
  /** The checks or the state of the pull request the session has may have moved: ask for it again. */
  states: boolean;
};

const START = String.raw`(?:^|[\s;&|("'\`/])`;
const END = String.raw`(?![\w-])`;
// `git -C dir -c key=value --no-pager push`: the options git takes before the command
const GIT = String.raw`${START}git(?:\s+-[Cc]\s+\S+|\s+--[\w-]+(?:=\S+)?)*\s+`;
const GH = String.raw`${START}gh\s+`;

const PUSH = new RegExp(`${GIT}push${END}`);
const MOVES_BRANCH = new RegExp(`${GIT}(?:checkout|switch)${END}`);
const PR_FOUND = new RegExp(`${GH}pr\\s+(?:create|checkout|co)${END}`);
const PR_CHANGES = new RegExp(`${GH}pr\\s+(?:merge|close|ready|reopen|review)${END}`);
const CHECKS_RERUN = new RegExp(`(?:${GH}run\\s+rerun|${GH}workflow\\s+run)${END}`);

/**
 * What the commands a turn ran may have changed at GitHub. A commit, an add or a status change nothing there, so they ask for nothing;
 * a push starts checks and may open the branch's pull request; `gh pr create` opens one; `gh pr merge` or `close` end one.
 * It reads the text only, never runs it, and a command it takes for another (an `echo "git push"`) costs one request too many, not one less.
 */
export function githubWorkOf(commands: readonly string[]): GithubWork {
  const work: GithubWork = { find: false, states: false };
  for (const command of commands) {
    if (PUSH.test(command)) work.find = work.states = true;
    if (MOVES_BRANCH.test(command) || PR_FOUND.test(command)) work.find = true;
    if (PR_CHANGES.test(command) || CHECKS_RERUN.test(command)) work.states = true;
  }
  return work;
}
