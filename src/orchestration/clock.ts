export interface Clock {
  now(): number;
  /** Runs fn once after ms; the returned function cancels it. */
  after(ms: number, fn: () => Promise<void>): () => void;
}

export const realClock: Clock = {
  now: () => Date.now(),
  after(ms, fn) {
    const timer = setTimeout(fn, ms);
    return () => clearTimeout(timer);
  },
};
