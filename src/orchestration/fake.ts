import type { Clock } from './clock.ts';
import { GitHubUnavailable, type GitHub } from './github.ts';

export class FakeGitHub implements GitHub {
  ready: Record<string, { issue: number; title: string }[]> = {};
  unavailable: GitHubUnavailable | null = null;
  /** Makes setLabels fail while the rest works. */
  setLabelsUnavailable: GitHubUnavailable | null = null;
  issues: Record<string, { state: 'open' | 'closed'; labels: string[] }> = {};
  pulls: Record<string, { state: 'open' | 'closed'; body: string; headSha: string }> = {};
  repoLabels: Record<string, string[]> = {};
  created: string[] = [];
  calls = 0;

  /** An issue not set up by the test is open and ready. */
  issue(repo: string, issue: number) {
    return (this.issues[`${repo}#${issue}`] ??= { state: 'open', labels: ['solve:epic:ready'] });
  }

  async listReadyEpics(repo: string) {
    this.calls++;
    if (this.unavailable) throw this.unavailable;
    return this.ready[repo] ?? [];
  }

  async getIssue(repo: string, issue: number) {
    const { state, labels } = this.issue(repo, issue);
    return { state, labels: [...labels] };
  }

  async getPullRequest(repo: string, number: number) {
    if (this.unavailable) throw this.unavailable;
    return this.pulls[`${repo}#${number}`] ?? null;
  }

  async setLabels(repo: string, issue: number, { add, remove }: { add: string[]; remove: string[] }) {
    if (this.setLabelsUnavailable) throw this.setLabelsUnavailable;
    const found = this.issue(repo, issue);
    found.labels = [...new Set([...found.labels.filter((l) => !remove.includes(l)), ...add])];
  }

  async listLabels(repo: string) {
    return [...(this.repoLabels[repo] ?? [])];
  }

  async createLabel(repo: string, name: string) {
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
