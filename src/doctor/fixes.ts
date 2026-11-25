import { defaultLabels } from '../orchestration/github.ts';
import type { CodedText } from '../orchestration/text-params.ts';
import { configDirVariable } from '../harnesses/names.ts';
import type { GitHubProfile } from '../integrations/github.ts';

// Every remedy lives here, with the code and parameters that stand for its words. They only repeat what a check already knows (names, owners): nothing from a child's output.
export const installFix: Record<string, CodedText> = {
  git: { code: 'doctor.fix.install', text: 'install git (xcode-select --install on macOS)', params: { tool: 'git' } },
  gh: { code: 'doctor.fix.install', text: 'install the GitHub CLI (https://cli.github.com) and run: gh auth login', params: { tool: 'gh' } },
  claude: { code: 'doctor.fix.install', text: 'install Claude Code (https://claude.com/claude-code) and sign in once', params: { tool: 'claude' } },
  codex: { code: 'doctor.fix.install', text: 'install the Codex CLI and run: codex login', params: { tool: 'codex' } },
  agy: { code: 'doctor.fix.install', text: 'install Antigravity and run agy once to sign in', params: { tool: 'agy' } },
  'agent-forge': { code: 'doctor.fix.install', text: 'install it: pnpm add -g @ashulab/agent-forge (https://github.com/AshuLab/agent-forge)', params: { tool: 'agent-forge' } },
};
export const fixes = {
  // `detail` is what the token request said, an external message: it is read here to pick the remedy and goes nowhere else.
  mint(profile: GitHubProfile, repo: string, detail: string): CodedText {
    if (profile.kind === 'gh') return { code: 'doctor.fix.ghLogin', text: 'run: gh auth login', params: {} };
    if (/agent not found/i.test(detail)) return { code: 'doctor.fix.agentNotFound', text: 'agent-forge --list shows your agents; add one with: agent-forge add', params: {} };
    if (/installation/i.test(detail)) return { code: 'doctor.fix.installApp', text: `install the GitHub App of that agent on ${repo.split('/')[0]}`, params: { owner: repo.split('/')[0]! } };
    if (/private key/i.test(detail)) return { code: 'doctor.fix.privateKey', text: 'check privateKeyPath of that agent in your Forge registry', params: {} };
    return { code: 'doctor.fix.mintOther', text: `run: agent-forge token --agent ${profile.agent} from a clone of the repo to see the full error`, params: { agent: profile.agent } };
  },
  read(repo: string, detail: string): CodedText | undefined {
    if (detail.includes('404')) {
      return {
        code: 'doctor.fix.repoNotVisible',
        text: `the repo does not exist or this identity cannot see it: install the App on ${repo.split('/')[0]} and give it access to ${repo}, or let Carrier read as another identity: orchestratorProfile in engine.json (Settings > Engine > GitHub identity)`,
        params: { owner: repo.split('/')[0]!, repo },
      };
    }
    if (detail.includes('401')) return { code: 'doctor.fix.credentialsRejected', text: "the identity's credentials were rejected: for gh run gh auth login, for a bot check its App in Forge", params: {} };
    return undefined;
  },
  solve: { code: 'doctor.fix.solveSetup', text: 'run solve:setup in the repo, it creates them', params: {} } as CodedText,
  ownLabels: (labels: string[]): CodedText => ({
    code: 'doctor.fix.ownLabels',
    text: `create ${labels.map((label) => `"${label}"`).join(', ')} in the repo (you named ${labels.length === 1 ? 'it' : 'them'} in labels): Solve creates only ${defaultLabels.epic} and ${defaultLabels.ready}`,
    params: { labels: labels.join(', '), count: labels.length, epic: defaultLabels.epic, ready: defaultLabels.ready },
  }),
  login(harness: 'claude' | 'codex' | 'agy', configDir: string | undefined): CodedText {
    if (harness === 'agy') return { code: 'doctor.fix.loginAgy', text: 'log in with: agy', params: {} };
    const command = harness === 'claude' ? 'claude /login' : 'codex login';
    if (configDir === undefined || configDir === '') return { code: 'doctor.fix.login', text: `log in with: ${command}`, params: { harness } };
    return { code: 'doctor.fix.loginAt', text: `log in with: ${configDirVariable[harness]}=${configDir} ${command}`, params: { harness, variable: configDirVariable[harness], configDir } };
  },
  command: (provider: string): CodedText => ({ code: 'doctor.fix.command', text: `fix "command" of the account ${provider} in providers.json: an absolute path to the CLI that runs`, params: { provider } }),
  skill: (name: string): CodedText => ({ code: 'doctor.fix.skill', text: `install the skill ${name} where that account finds it, or name another one in "skills" of engine.json`, params: { skill: name } }),
  skillUnread: { code: 'doctor.fix.skillUnread', text: 'check the output of the harness\'s plugin list, the permissions of the folders it reads and any skills manifest (include_only and exclude hide skills from the check); troubleshooting.md lists where each harness is read', params: {} } as CodedText,
  socketPath: { code: 'doctor.fix.socketPath', text: 'move the Carrier folder to a shorter path (CARRIER_HOME, at most 77 bytes)', params: { max: 77 } } as CodedText,
  serverDown: { code: 'doctor.fix.serverDown', text: 'start the server (LM Studio: lms server start, Ollama: ollama serve) and download the model', params: {} } as CodedText,
  modelMissing: (model: string): CodedText => ({ code: 'doctor.fix.modelMissing', text: `download it in LM Studio / ollama pull ${model}`, params: { model } }),
};
