/** Flags answer questions ahead of time; whatever is missing is asked. */
/** `identities` is `separate` or `shared`. `authorProfile` / `reviewerProfile` are `forge:<agent>` or `gh`; `author` / `reviewer` are `<harness>:<model>`; `authorProvider` / `reviewerProvider` are `lmstudio` or `ollama` when that model runs there; the persona flags are the name and prompt of a role's persona. */
export type InitFlags = {
  repo?: string[];
  identities?: string;
  authorProfile?: string;
  reviewerProfile?: string;
  leadReviewerProfile?: string;
  author?: string;
  reviewer?: string;
  leadReviewer?: string;
  authorProvider?: string;
  reviewerProvider?: string;
  leadReviewerProvider?: string;
  authorPersonaName?: string;
  authorPersonaPrompt?: string;
  reviewerPersonaName?: string;
  reviewerPersonaPrompt?: string;
  leadReviewerPersonaName?: string;
  leadReviewerPersonaPrompt?: string;
  out?: string;
  yes?: boolean;
};
