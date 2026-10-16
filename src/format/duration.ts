// "45s", "3m 05s", "2h 03m", "1d 4h": the two largest units, for the panel and anything else that shows elapsed time.
export function formatDuration(ms: number): string {
  const s = Math.floor(Math.max(0, ms) / 1000);
  const [d, h, m] = [Math.floor(s / 86_400), Math.floor((s % 86_400) / 3600), Math.floor((s % 3600) / 60)];
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m`;
  if (m > 0) return `${m}m ${String(s % 60).padStart(2, '0')}s`;
  return `${s}s`;
}
