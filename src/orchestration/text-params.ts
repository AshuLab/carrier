/** The values a text code takes: plain strings and numbers, never a sentence, an object or a boolean. The engine's refusals and the chat's share it, so it lives where neither imports the other. */
export type TextParams = Record<string, string | number>;

/** A text with its code and parameters beside its words: the shape of a doctor check's detail or fix and of the reason an epic needs a human, before each is put in its own fields. */
export type CodedText = { code: string; text: string; params: TextParams };
