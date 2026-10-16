import type { Clock } from './clock.ts';
import { GitHubUnavailable, type GitHub } from './github.ts';

export class FakeGitHub implements GitHub {
  ready: Record<string, { issue: number; title: string }[]> = {};
  unavailable: GitHubUnavailable | null = null;
  calls = 0;

  async listReadyEpics(repo: string) {
    this.calls++;
    if (this.unavailable) throw this.unavailable;
    return this.ready[repo] ?? [];
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
