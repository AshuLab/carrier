import { redact } from '../logging/redact.ts';

/** Redacted first, then one line, then cut: in that order, so a token cut in half cannot slip through. */
export const failureDetail = (text: string) => redact(text).replace(/\s+/g, ' ').trim().slice(0, 300);
