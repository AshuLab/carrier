import type { GitHubProfile } from '../integrations/github.ts';

// Every remedy lives here. They only repeat what a check already knows (names, owners): nothing from a child's output.
export const installFix: Record<string, string> = {
  git: 'install git (xcode-select --install on macOS)',
  gh: 'install the GitHub CLI (https://cli.github.com) and run: gh auth login',
  claude: 'install Claude Code (https://claude.com/claude-code) and sign in once',
  codex: 'install the Codex CLI and run: codex login',
  agy: 'install Antigravity and run agy once to sign in',
  'agent-forge': 'install it: pnpm add -g @ashulab/agent-forge (https://github.com/AshuLab/agent-forge)',
};
export const fixes = {
  mint(profile: GitHubProfile, repo: string, detail: string) {
    if (profile.kind === 'gh') return 'run: gh auth login';
    if (/agent not found/i.test(detail)) return 'agent-forge --list shows your agents; add one with: agent-forge add';
    if (/installation/i.test(detail)) return `install the GitHub App of that agent on ${repo.split('/')[0]}`;
    if (/private key/i.test(detail)) return 'check privateKeyPath of that agent in your Forge registry';
    return `run: agent-forge token --agent ${profile.agent} from a clone of the repo to see the full error`;
  },
  read(repo: string, detail: string) {
    if (detail.includes('404')) return `the repo does not exist or this identity cannot see it: install the App on ${repo.split('/')[0]} and give it access to ${repo}`;
    if (detail.includes('401')) return "the identity's credentials were rejected: for gh run gh auth login, for a bot check its App in Forge";
    return undefined;
  },
  socketPath: 'move the shared root to a shorter path (root in the config, at most 77 bytes)',
  clash: 'use two different bots (agent-forge add) or one bot and your gh login',
  serverDown: 'start the server (LM Studio: lms server start, Ollama: ollama serve) and download the model',
  modelMissing: (model: string) => `download it in LM Studio / ollama pull ${model}`,
};
