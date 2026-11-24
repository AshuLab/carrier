/** The values a text code takes: plain strings and numbers, never a sentence, an object or a boolean. The engine's refusals and the chat's share it, so it lives where neither imports the other. */
export type TextParams = Record<string, string | number>;
