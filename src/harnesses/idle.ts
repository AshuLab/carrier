/** Has a process written nothing for `idleMs`? Absent `idleMs` means no watchdog. */
export const isIdle = (now: number, lastOutputAt: number, idleMs: number | undefined) => idleMs !== undefined && now - lastOutputAt >= idleMs;
