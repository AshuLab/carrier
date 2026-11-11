/** Flags answer questions ahead of time; whatever is missing is asked. */
/** `authorProfile` / `reviewerProfile` are `forge:<agent>` or `gh`; `author` / `reviewer` are `<harness>:<model>`; `authorProvider` / `reviewerProvider` are `lmstudio` or `ollama` when that model runs there; the effort flags are one of the five levels; the persona flags are the name and prompt of a role's persona. */
export type InitFlags = {
  repo?: string[];
  authorProfile?: string;
  reviewerProfile?: string;
  leadReviewerProfile?: string;
  author?: string;
  reviewer?: string;
  leadReviewer?: string;
  authorProvider?: string;
  reviewerProvider?: string;
  leadReviewerProvider?: string;
  authorEffort?: string;
  reviewerEffort?: string;
  leadReviewerEffort?: string;
  authorPersonaName?: string;
  authorPersonaPrompt?: string;
  reviewerPersonaName?: string;
  reviewerPersonaPrompt?: string;
  leadReviewerPersonaName?: string;
  leadReviewerPersonaPrompt?: string;
  out?: string;
  yes?: boolean;
};
