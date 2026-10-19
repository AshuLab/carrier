/** Flags answer questions ahead of time; whatever is missing is asked. */
/** `authorProfile` / `reviewerProfile` are `forge:<agent>` or `gh`; `author` / `reviewer` are `<harness>:<model>`; `authorProvider` / `reviewerProvider` are `lmstudio` or `ollama` when that model runs there. */
export type InitFlags = { repo?: string[]; authorProfile?: string; reviewerProfile?: string; author?: string; reviewer?: string; authorProvider?: string; reviewerProvider?: string; out?: string; yes?: boolean };
