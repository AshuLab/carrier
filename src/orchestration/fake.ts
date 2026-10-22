import type { Clock } from './clock.ts';
import { AuthError, GitHubUnavailable, type EpicSlice, type PullRequestBlock, type GitHub, type LabelStyle, type RateLimit, type Slices } from './github.ts';

export class FakeGitHub implements GitHub {
  /** What rateLimit answers. */
  limit: RateLimit | null = null;
  rateLimit() {
    return this.limit;
  }
  /** A ready epic's labels are the issue's, as GitHub lists them. */
  ready: Record<string, { issue: number; title: string }[]> = {};
  unavailable: GitHubUnavailable | null = null;
  /** The open epics with their slice progress, by repo; the title defaults to empty and the labels to the issue's. */
  openEpics: Record<string, { issue: number; title?: string; slices: Slices | null }[]> = {};
  /** Makes listOpenEpics fail while the rest works. */
  openEpicsUnavailable: GitHubUnavailable | null = null;
  /** What readSlices answers, by `repo#issue`; an epic not listed has no slices. */
  slices: Record<string, { slices: EpicSlice[]; truncated?: boolean }> = {};
  /** Makes readSlices fail while the rest works. */
  slicesUnavailable: GitHubUnavailable | null = null;
  /** Every slice read that reached the port, as `repo#issue`. */
  sliceReads: string[] = [];
  /** What readPullRequest answers, by `repo#number`; a pull request not listed does not exist. */
  pullRequestBlocks: Record<string, PullRequestBlock> = {};
  /** Makes readPullRequest fail while the rest works. */
  pullRequestUnavailable: GitHubUnavailable | null = null;
  /** Every pull request read that reached the port, as `repo#number`. */
  pullRequestReads: string[] = [];
  /** Makes setLabels fail while the rest works. */
  setLabelsUnavailable: GitHubUnavailable | null = null;
  issues: Record<string, { state: 'open' | 'closed'; labels: string[] }> = {};
  pulls: Record<string, { state: 'open' | 'closed' | 'merged'; body: string; headSha: string; headRef?: string }> = {};
  repoLabels: Record<string, string[]> = {};
  created: string[] = [];
  /** The colour and description each label was created with. */
  styles: Record<string, LabelStyle> = {};
  calls = 0;
  /** Makes every call fail like Forge rejecting the orchestrator's profile. */
  authError: AuthError | null = null;
  /** Every call that reached the port, failed or not. */
  attempts = 0;

  private guard() {
    this.attempts++;
    if (this.authError) throw this.authError;
  }

  /** An issue not set up by the test is open and ready. */
  issue(repo: string, issue: number) {
    return (this.issues[`${repo}#${issue}`] ??= { state: 'open', labels: ['solve:epic:ready'] });
  }

  async listReadyEpics(repo: string) {
    this.guard();
    this.calls++;
    if (this.unavailable) throw this.unavailable;
    return (this.ready[repo] ?? []).filter((e) => this.issue(repo, e.issue).labels.includes('solve:epic:ready')).map((e) => ({ ...e, labels: [...this.issue(repo, e.issue).labels] })); // like GitHub: the label decides
  }

  async listOpenEpics(repo: string) {
    this.guard();
    const failure = this.unavailable ?? this.openEpicsUnavailable;
    if (failure) throw failure;
    return (this.openEpics[repo] ?? []).map((epic) => ({ title: '', ...epic, labels: [...(this.issues[`${repo}#${epic.issue}`]?.labels ?? [])] }));
  }

  async readSlices(repo: string, issue: number) {
    this.guard();
    this.sliceReads.push(`${repo}#${issue}`);
    if (this.slicesUnavailable) throw this.slicesUnavailable;
    const found = this.slices[`${repo}#${issue}`];
    return { slices: found?.slices.map((s) => ({ ...s })) ?? [], truncated: found?.truncated ?? false };
  }

  async readPullRequest(repo: string, number: number) {
    this.guard();
    this.pullRequestReads.push(`${repo}#${number}`);
    if (this.pullRequestUnavailable) throw this.pullRequestUnavailable;
    const found = this.pullRequestBlocks[`${repo}#${number}`];
    return found === undefined ? null : { ...found, checks: found.checks && { ...found.checks } };
  }

  async getIssue(repo: string, issue: number) {
    this.guard();
    const { state, labels } = this.issue(repo, issue);
    return { state, labels: [...labels] };
  }

  async getPullRequest(repo: string, number: number) {
    this.guard();
    if (this.unavailable) throw this.unavailable;
    const pull = this.pulls[`${repo}#${number}`];
    return pull ? { ...pull, headRef: pull.headRef ?? 'feat/epic/epic' } : null;
  }

  async findPullRequest(repo: string, issue: number) {
    this.guard();
    if (this.unavailable) throw this.unavailable;
    for (const [key, { state, body, headSha }] of Object.entries(this.pulls)) {
      if (key.startsWith(`${repo}#`) && new RegExp(`\\bcloses #${issue}(?!\\d)`, 'i').test(body)) return { number: Number(key.split('#')[1]), state, headSha };
    }
    return null;
  }

  async setLabels(repo: string, issue: number, { add, remove }: { add: string[]; remove: string[] }) {
    this.guard();
    if (this.setLabelsUnavailable) throw this.setLabelsUnavailable;
    const found = this.issue(repo, issue);
    found.labels = [...new Set([...found.labels.filter((l) => !remove.includes(l)), ...add])];
  }

  async listLabels(repo: string) {
    this.guard();
    return [...(this.repoLabels[repo] ?? [])];
  }

  async createLabel(repo: string, name: string, style: LabelStyle) {
    this.guard();
    this.styles[name] = style;
    (this.repoLabels[repo] ??= []).push(name);
    this.created.push(`${repo}:${name}`);
  }
}

export class FakeClock implements Clock {
  time = 0;
  private timers: { at: number; fn: () => Promise<void> }[] = [];

  now() {
    return this.time;
  }

  after(ms: number, fn: () => Promise<void>) {
    const timer = { at: this.time + ms, fn };
    this.timers.push(timer);
    return () => {
      this.timers = this.timers.filter((t) => t !== timer);
    };
  }

  /** Moves time forward, running due timers in order and waiting for each to finish. */
  async advance(ms: number) {
    const target = this.time + ms;
    for (;;) {
      const next = this.timers.filter((t) => t.at <= target).sort((a, b) => a.at - b.at)[0];
      if (!next) break;
      this.timers = this.timers.filter((t) => t !== next);
      this.time = next.at;
      await next.fn();
    }
    this.time = target;
  }
}
