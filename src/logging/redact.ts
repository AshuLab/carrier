// Replaces what looks like a secret. A pattern list can miss one (ADR 0006): this is a mitigation, not a guarantee.
// Order matters: a private key block goes first, because its body would match nothing else but is the biggest leak.
const patterns: RegExp[] = [
  // To the END line, or to the end of the text when the block was cut.
  /-----BEGIN [A-Z ]*PRIVATE KEY(?: BLOCK)?-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY(?: BLOCK)?-----|$)/g,
  // The header's value, with or without a scheme (Bearer, Basic, token).
  /\bAuthorization\s*:\s*(?:(?:Bearer|Basic|Digest|Negotiate|Token)\s+)?[^\s"']+/gi,
  // NAME=value where the name holds SECRET, TOKEN, PASSWORD or KEY; the value is quoted or runs to a space.
  /\b\w*(?:SECRET|TOKEN|PASSWORD|KEY)\w*=(?!=)(?:"[^"]*"|'[^']*'|[^\s"']+)/gi,
  /\b(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]+/g, // GitHub: classic, OAuth, user, server, refresh, fine-grained
  /\bsk-[A-Za-z0-9_-]{16,}/g, // OpenAI, Anthropic (sk-ant-), OpenRouter
  /\b[sr]k_(?:live|test)_[A-Za-z0-9]{16,}/g, // Stripe
  /\bAKIA[0-9A-Z]{16}\b/g, // AWS access key id
  /\bAIza[0-9A-Za-z_-]{35}/g, // Google API key
  /\bxox[abeprs]-[A-Za-z0-9-]{10,}/g, // Slack
  /\bglpat-[A-Za-z0-9_-]{20,}/g, // GitLab
  /\bnpm_[A-Za-z0-9]{36}\b/g, // npm
  /\bhf_[A-Za-z0-9]{30,}/g, // Hugging Face
  /\beyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}/g, // JWT
];

export const redact = (text: string): string => patterns.reduce((out, pattern) => out.replace(pattern, '[redacted]'), text);
