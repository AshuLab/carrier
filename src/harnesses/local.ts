export const localKinds = ['lmstudio', 'ollama'] as const;
export type LocalProvider = (typeof localKinds)[number];

export const localLabel: Record<LocalProvider, string> = { lmstudio: 'LM Studio', ollama: 'Ollama' };

// ponytail: default ports only; a server on another port needs a base-URL setting when someone runs one.
export const localUrl: Record<LocalProvider, string> = { lmstudio: 'http://localhost:1234', ollama: 'http://localhost:11434' };

/** The environment that points the Claude CLI at a local server, which speaks the Anthropic API on its root URL. */
export const claudeLocalEnv = (local: LocalProvider): Record<string, string> => ({
  ANTHROPIC_BASE_URL: localUrl[local],
  ANTHROPIC_AUTH_TOKEN: local, // any non-empty value: the local server does not check it
  ANTHROPIC_API_KEY: '', // a real key in the user's environment must not be sent to a local server
});

/** The chat models the server has. Throws when it does not answer, which is how callers tell "not running". */
export async function listLocalModels(local: LocalProvider, fetchJson: (url: string) => Promise<unknown> = defaultFetch): Promise<string[]> {
  if (local === 'ollama') {
    const body = (await fetchJson(`${localUrl.ollama}/api/tags`)) as { models?: { name?: string }[] };
    return (body.models ?? []).flatMap((m) => (m.name ? [m.name] : []));
  }
  const body = (await fetchJson(`${localUrl.lmstudio}/v1/models`)) as { data?: { id?: string }[] };
  return (body.data ?? []).flatMap((m) => (m.id && !/embed/i.test(m.id) ? [m.id] : [])); // LM Studio lists embedding models too
}

async function defaultFetch(url: string) {
  const response = await fetch(url, { signal: AbortSignal.timeout(2000) });
  if (!response.ok) throw new Error(`${url} answered HTTP ${response.status}`);
  return response.json();
}
