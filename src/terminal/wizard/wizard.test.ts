import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { stripVTControlCharacters } from 'node:util';
import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../config/load.ts';
import { Back, Cancelled, type Ui } from '../prompts/types.ts';
import { realDeps } from './deps.ts';
import type { InitFlags } from './flags.ts';
import { asFiles, fakeDeps, fakeMachine, okCheck, providersWritten, quietUi, useTempDir } from './testing.ts';
import { runInit } from './wizard.ts';

const dir = useTempDir();
const notNow = 'Start Carrier now?'; // Enter would start it

const withHome = async <T>(run: () => Promise<T>) => {
  process.env.CARRIER_HOME = join(dir, 'home');
  try {
    return await run();
  } finally {
    delete process.env.CARRIER_HOME;
  }
};

const existingKey = `A config already exists at ${join(dir, 'home', 'engine.json')}`;

const existing = {
  repos: [{ name: 'X/y' }, { name: 'X/z' }],
  profiles: { 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' }, gh: { kind: 'gh' } },
  orchestratorProfile: 'tassadar-agent',
  providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } },
  agents: {
    author: { profile: 'tassadar-agent', provider: 'claude', model: 'opus' },
    reviewer: { profile: 'gh', provider: 'codex', model: 'gpt-test' },
  },
};

test('the questions fill a config that has only what defaults lack, and the doctor runs on it', async () => {
  let doctored: unknown;
  const { deps, written } = fakeDeps({ doctor: async (config) => ((doctored = config), [okCheck]) });
  const { ui, asked } = quietUi({ 'Repos to watch (owner/name, comma separated, or none for now)': 'AshuLab/a, AshuLab/b', [notNow]: false });
  const out = join(dir, 'a.json');
  const result = await runInit({ out }, ui, deps);

  expect(JSON.parse(written[out]!)).toEqual({
    repos: [{ name: 'AshuLab/a' }, { name: 'AshuLab/b' }],
    profiles: { 'artanis-agent': { kind: 'forge', agent: 'artanis-agent' }, 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' } },
    orchestratorProfile: 'artanis-agent',
    agents: {
      author: { profile: 'artanis-agent', provider: 'claude', model: 'sonnet', effort: 'high' },
      reviewer: { profile: 'tassadar-agent', provider: 'codex', model: 'gpt-test', effort: 'high' }, // author's bot is not offered again; codex default from ~/.codex
    },
  });
  expect(providersWritten(written)).toEqual({ claude: { harness: 'claude' }, codex: { harness: 'codex' } });
  expect(doctored).toMatchObject({ pollIntervalMinutes: 5, providers: { claude: { harness: 'claude' } } }); // the doctor gets the merged config, accounts included
  expect(result.checks).toEqual([okCheck]);
  expect(asked.at(-1)).toContain(`carrier --config ${out}`);
});

test('every flag skips its question', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'b.json');
  await runInit({ repo: ['AshuLab/x'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'codex:m1', reviewer: 'claude:m2', out, yes: true }, ui, deps);
  expect(asked.filter((a) => !a.startsWith('outro') && !a.startsWith('checks:'))).toEqual([]);
  const config = JSON.parse(written[out]!);
  expect(config).not.toHaveProperty('providers');
  expect(providersWritten(written)).toEqual({ claude: { harness: 'claude' }, codex: { harness: 'codex' } }); // the flags name what was detected
  expect(config.agents).toEqual({ author: { profile: 'artanis-agent', provider: 'codex', model: 'm1', effort: 'high' }, reviewer: { profile: 'gh', provider: 'claude', model: 'm2', effort: 'high' } });
  expect(loadConfig(defaults, config, providersWritten(written) as never).ok).toBe(true);

  // --author and --reviewer together also skip the failover question when the run is not --yes
  const interactive = fakeDeps();
  const { ui: talking, asked: talked } = quietUi();
  await runInit({ repo: ['AshuLab/x'], authorProfile: 'gh', reviewerProfile: 'gh', author: 'codex:m1', reviewer: 'claude:m2', out: join(dir, 'b2.json') }, talking, interactive.deps);
  expect(talked.some((q) => /failover/i.test(q))).toBe(false);
});

test('providers are not asked: what the detector found is shown and written switched off, with the extras asked for, and the recap says where the file goes', async () => {
  const { deps, written } = fakeDeps({ machine: fakeMachine({ version: async (command) => (command.endsWith('claude') ? '2.1.3' : '0.5.0'), login: async (harness) => (harness === 'codex' ? 'out' : 'in'), localModels: async (kind) => (kind === 'ollama' ? ['qwen3:8b'] : Promise.reject(new Error('down'))) }) });
  const { ui, asked, notes } = quietUi({ 'Add another account?': [true, false], 'Which agent CLI runs this account?': 'claude', 'Where does this account run?': 'ollama' });
  const out = join(dir, 'd.json');
  const folder = join(dir, 'carrier-home');
  await runInit({ repo: ['A/b'], out }, ui, deps, folder);
  expect(asked.indexOf('Which agent CLI runs this account?')).toBeGreaterThan(asked.indexOf('Add another account?')); // only the extras are asked, after the gate
  expect(notes.find((n) => n.title === 'Found on this Mac')!.message).toBe(
    ['Claude Code  /opt/bin/claude · 2.1.3 · signed in', 'Codex        /opt/bin/codex · 0.5.0 · signed out', 'Antigravity  not found', 'LM Studio    not running', 'Ollama       running · 1 models'].join('\n'),
  );
  expect(providersWritten(written, folder)).toEqual({ claude: { harness: 'claude' }, codex: { harness: 'codex' }, 'claude-2': { harness: 'claude', provider: 'ollama' } });
  expect(stripVTControlCharacters(notes.find((n) => n.title === 'AI accounts')!.message)).toContain('2 accounts were added for the agent CLIs found on this Mac that had none'); // what was found is said to be already there
  expect(notes.find((n) => n.title === 'This is what will be saved')!.message).toContain(`Accounts file ${join(folder, 'providers.json')}`); // not next to --out
});

test('a flag adds its account to the file, and an unattended run asks nothing', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const folder = join(dir, 'carrier-home-e');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'claude:m1', authorProvider: 'ollama', reviewer: 'codex:m2', out: join(dir, 'e.json'), yes: true }, ui, deps, folder);
  expect(asked.filter((a) => !a.startsWith('outro') && !a.startsWith('checks:'))).toEqual([]);
  expect(providersWritten(written, folder)).toEqual({ claude: { harness: 'claude' }, codex: { harness: 'codex' }, 'claude-author': { harness: 'claude', provider: 'ollama' } });
});

test('failed checks are reported in the closing line', async () => {
  const { deps } = fakeDeps({ doctor: async () => [{ name: 'gh installed', status: 'fail' }] });
  const { ui, asked } = quietUi();
  await runInit({ out: join(dir, 'g.json') }, ui, deps);
  expect(asked.at(-1)).toContain('1 check failed');
  expect(asked.at(-1)).toContain('carrier doctor --config');
});

test('each role is one block: its questions come together, and the author is closed before the reviewer', async () => {
  const { ui, asked, notes } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'o.json') }, ui, fakeDeps().deps);
  expect(notes.map((n) => n.title).filter((t) => t === 'Author' || t === 'Reviewer')).toEqual(['Author', 'Reviewer']);
  expect(asked.filter((m) => /author|reviewer|^Model and effort/i.test(m) && !m.startsWith('outro'))).toEqual([
    'GitHub profile for the author',
    'Which account runs the author?',
    'Model and effort: sonnet at high, change them?',
    "Customise the author's persona?",
    'Turn failover on for the author? When it runs out of credits it moves to the steps you list, each an account and a model.',
    'GitHub profile for the reviewer',
    'Which account runs the reviewer?',
    'Model and effort: gpt-test at high, change them?',
    "Customise the reviewer's persona?",
    'Turn failover on for the reviewer? When it runs out of credits it moves to the steps you list, each an account and a model.',
    'Add another reviewer?',
    'Add a lead reviewer?',
  ]);
});

test('the recap lists what will be saved, and declining it writes nothing', async () => {
  const { deps, written } = fakeDeps();
  const notes: Record<string, string> = {};
  const { ui } = quietUi({ 'Save it?': 'cancel' });
  const spy: Ui = { ...ui, note: (m, title) => void (notes[title] = m) };
  await expect(runInit({ repo: ['A/b'], out: join(dir, 'u.json') }, spy, deps)).rejects.toBeInstanceOf(Cancelled);
  expect(written).toEqual({});
  expect(notes['This is what will be saved']).toMatch(/Repos {9}A\/b\nOrchestrator {2}artanis-agent\nAccounts {6}claude, codex\nAuthor {8}artanis-agent · claude \(Claude Code\) · sonnet · high\nReviewer {6}tassadar-agent · codex \(Codex\) · gpt-test · high\nConfig {8}/);
});

test('--yes skips the recap and the start question', async () => {
  const { deps } = fakeDeps();
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'v.json'), yes: true }, ui, deps);
  expect(asked).not.toContain('Save it?');
  expect(asked.some((q) => q.startsWith('Start Carrier'))).toBe(false);
});

test('--yes prints the recap of what it chose, before the checks run', async () => {
  const order: string[] = [];
  const { deps } = fakeDeps({ doctor: async () => (order.push('checks'), [okCheck]) });
  const { ui } = quietUi();
  const out = join(dir, 'yes-recap.json');
  await runInit({ repo: ['A/b'], out, yes: true }, { ...ui, note: (m, title) => void (title === 'This is what will be saved' && order.push(m)) }, deps);
  expect(order).toHaveLength(2);
  expect(order[1]).toBe('checks');
  expect(order[0]).toMatch(/Repos {9}A\/b\nOrchestrator {2}artanis-agent\nAccounts {6}claude, codex\nAuthor {8}artanis-agent · claude \(Claude Code\) · sonnet · high\nReviewer {6}tassadar-agent · codex \(Codex\) · gpt-test · high\nConfig {8}.*yes-recap\.json\nAccounts file /);
});

test('Ctrl+C at "Start Carrier now?" after the save is a no: the files stay and the closing line says what to run', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'late-cancel.json');
  const questions: string[] = [];
  const spy: Ui = {
    ...ui,
    confirm: async (message, initialValue) => {
      questions.push(message);
      if (message === notNow) throw new Cancelled();
      return ui.confirm(message, initialValue);
    },
  };
  const result = await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(result.start).toBe(false);
  expect(Object.keys(written)).toContain(out);
  expect(asked.at(-1)).toContain(`outro:Ready. Start it with: carrier --config ${out}`);
  expect(questions.at(-1)).toBe(notNow);
  expect(notNow).not.toContain('Ctrl+C');
});

test('Ctrl+C at an earlier question still cancels with nothing written', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi();
  const spy: Ui = { ...ui, select: async (question) => (question.message === 'Save it?' ? Promise.reject(new Cancelled()) : ui.select(question)) };
  await expect(runInit({ repo: ['A/b'], out: join(dir, 'early-cancel.json') }, spy, deps)).rejects.toBeInstanceOf(Cancelled);
  expect(written).toEqual({});
});

test('without a terminal and without --yes, a file that is already there is refused with how to go on', async () => {
  const { deps, written } = fakeDeps({ exists: () => true });
  const { ui } = quietUi();
  const flags = { repo: ['A/b'], out: join(dir, 'there.json') };
  await expect(runInit(flags, { ...ui, interactive: false }, deps)).rejects.toThrow(/there\.json already exists: pass --yes to replace it, or --out to write another file/);
  expect(written).toEqual({});
});

test('an existing config can be edited: its answers are the starting points and no question about the file is asked', async () => {
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(existing) });
  const { ui, asked } = quietUi();
  await withHome(() => runInit({}, ui, deps));
  const [path] = Object.keys(written);
  expect(path).toBe(join(dir, 'home', 'engine.json'));
  const { providers, ...config } = existing;
  expect(JSON.parse(written[path!]!)).toEqual(config);
  expect(providersWritten(written, join(dir, 'home'))).toEqual(providers); // the existing accounts are the starting points
  expect(asked).not.toContain('Where should the config be saved?');
  expect(asked.some((q) => q.endsWith('exists. Overwrite it?'))).toBe(false);
});

test('"Start over" ignores the old answers but still replaces that file without asking again', async () => {
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(existing) });
  const { ui } = quietUi({ [existingKey]: 'fresh' });
  await withHome(() => runInit({}, ui, deps));
  expect(JSON.parse(written[join(dir, 'home', 'engine.json')]!).repos).toEqual([{ name: 'AshuLab/carrier' }]); // the origin suggestion, not the old repos
});

test('--author and --reviewer together keep the file\'s failover without asking about it', async () => {
  const withFailover = { ...existing, failover: { triggers: ['usage_limit'], roles: { author: [{ provider: 'codex', model: 'gpt-test' }] } } };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(withFailover) });
  const { ui, asked } = quietUi({ [existingKey]: 'edit' });
  await withHome(() => runInit({ author: 'claude:m1', reviewer: 'codex:m2', authorProfile: 'gh', reviewerProfile: 'gh', repo: ['A/b'] }, ui, deps));
  expect(asked.some((q) => /failover/i.test(q))).toBe(false);
  expect(JSON.parse(written[join(dir, 'home', 'engine.json')]!).failover.roles.author).toEqual([{ provider: 'codex', model: 'gpt-test' }]);
});

test('"Leave it as it is" cancels, and an unreadable config is said so instead of crashing', async () => {
  const left = fakeDeps({ exists: () => true });
  await expect(withHome(() => runInit({}, quietUi({ [existingKey]: 'cancel' }).ui, left.deps))).rejects.toBeInstanceOf(Cancelled);
  expect(left.written).toEqual({});
  const broken = fakeDeps({ exists: () => true, readConfig: (path) => (path.endsWith('providers.json') ? {} : { nope: 1 }) });
  const { ui, asked } = quietUi();
  await expect(withHome(() => runInit({}, ui, broken.deps))).rejects.toBeInstanceOf(Cancelled); // it is not replaced unless the person says so
  expect(asked.some((q) => q.startsWith('warn:') && q.includes('does not validate, first error:'))).toBe(true);
  expect(broken.written).toEqual({});
});

test('after good checks it shows what is waiting and offers to start; with failed checks it does neither', async () => {
  const notes: Record<string, string> = {};
  const good = fakeDeps({ readyEpics: async () => ({ 'AshuLab/carrier': 2, 'AshuLab/x': undefined }) });
  const { ui, asked: started } = quietUi({ [notNow]: true });
  const result = await runInit({ repo: ['A/b'], out: join(dir, 'z.json') }, { ...ui, note: (m, t) => void (notes[t] = m) }, good.deps);
  expect(result.start).toBe(true);
  expect(started.some((m) => m.startsWith('outro:'))).toBe(false); // the frame stays open for the arrival line
  expect(notes['Waiting for Carrier']).toBe('AshuLab/carrier: 2 epics marked ready\nAshuLab/x: could not read');

  let asked = 0;
  const bad = fakeDeps({ doctor: async () => [{ name: 'gh installed', status: 'fail' }], readyEpics: async () => (asked += 1, {}) });
  const failed = await runInit({ repo: ['A/b'], out: join(dir, 'z2.json') }, quietUi().ui, bad.deps);
  expect([failed.start, asked]).toEqual([false, 0]);
});

test('a machine that is fine shows nothing about itself, and the checks end with one count', async () => {
  const notes: string[] = [];
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'm1.json') }, { ...ui, note: (_m, t) => void notes.push(t) }, fakeDeps().deps);
  expect(notes).not.toContain('This machine');
  expect(asked).toContain('checks:1/0'); // the fake doctor ran one check
  expect(asked.some((q) => q.startsWith('warn:'))).toBe(false);
});

test('what cannot work at all stops before any question, each with how to fix it', async () => {
  const { ui, asked } = quietUi();
  await expect(runInit({ repo: ['A/b'] }, ui, fakeDeps({ which: (c) => c !== 'gh' }).deps)).rejects.toThrow(/Carrier needs these before it can run:\n {2}gh: install the GitHub CLI/);
  await expect(runInit({ repo: ['A/b'] }, ui, fakeDeps({ machine: fakeMachine({ resolveBinary: () => { throw new Error('not found'); } }) }).deps)).rejects.toThrow(/an agent CLI, any of these:\n {4}claude: install Claude Code .*\n {4}codex: .*\n {4}agy: /);
  expect(asked).toEqual([]); // nothing was asked
});

test('gh without a login is a warning, not a stop', async () => {
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'm2.json') }, ui, fakeDeps({ ghLogin: () => undefined }).deps);
  expect(asked.find((q) => q.startsWith('warn:gh is not logged in'))).toContain('gh auth login');
});

// Efforts: asked after each model, or given by flag; edit mode starts from the file's.
test('the effort of each role is asked after its model when the person changes them, written when chosen, and the config loads', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi({ 'Model and effort: sonnet at high, change them?': true, 'Effort for the author': '\0unset', 'Model and effort: gpt-test at high, change them?': true, 'Effort for the reviewer': 'xhigh' });
  const out = join(dir, 'ef1.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  const user = JSON.parse(written[out]!);
  expect(user.agents.author).not.toHaveProperty('effort'); // "the CLI's own" is not written
  expect(user.agents.reviewer.effort).toBe('xhigh');
  expect(user).not.toHaveProperty('identities');
  expect(loadConfig(defaults, user, providersWritten(written) as never).ok).toBe(true);
});

test('--yes with the effort flags writes them, and one outside the five levels is an error naming the flag', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'ef2.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'claude:m1', reviewer: 'codex:m2', authorEffort: 'low', reviewerEffort: 'max', out, yes: true }, ui, deps);
  expect(asked.filter((q) => !q.startsWith('outro') && !q.startsWith('checks:'))).toEqual([]);
  expect(JSON.parse(written[out]!).agents).toMatchObject({ author: { effort: 'low' }, reviewer: { effort: 'max' } });
  await expect(runInit({ repo: ['A/b'], authorEffort: 'Max', out: join(dir, 'ef3.json'), yes: true }, quietUi().ui, fakeDeps().deps)).rejects.toThrow('--author-effort "Max": expected low, medium, high, xhigh, max');
});

test('editing a config starts from its efforts and its failover steps, and the recap shows a shared identity', async () => {
  const shared = {
    repos: [{ name: 'X/y' }],
    profiles: { gh: { kind: 'gh' } },
    orchestratorProfile: 'gh',
    providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } },
    failover: { roles: { author: [{ provider: 'codex', model: 'gpt-x' }] } },
    agents: {
      author: { profile: 'gh', provider: 'claude', model: 'opus', effort: 'high' },
      reviewer: { profile: 'gh', provider: 'codex', model: 'gpt-test' },
    },
  };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(shared) });
  const { ui } = quietUi({ 'Model and effort: opus at high, change them?': true });
  const initial: Record<string, unknown> = {};
  const notes: Record<string, string> = {};
  await withHome(() => runInit({}, { ...ui, select: async (o) => ((initial[o.message] = o.initialValue), ui.select(o)), note: (m, t) => void (notes[t] = m) }, deps));
  expect(initial['Model for the author']).toBe('opus'); // the file's, not sonnet
  expect(initial['Effort for the author']).toBe('high');
  expect(initial['GitHub profile for the author']).toBe('gh');
  expect(notes['This is what will be saved']).toContain('Profile       shared: author and reviewer act as the same GitHub account, and the signature in what they publish will show it');
  const { providers, ...config } = shared;
  expect(JSON.parse(written[join(dir, 'home', 'engine.json')]!)).toEqual(config);
  expect(providersWritten(written, join(dir, 'home'))).toEqual(providers);
});

// Personas: a name and a prompt per role, asked right after its agent.
const titled = (role: string) => role.split(' ').map((w) => `${w[0]!.toUpperCase()}${w.slice(1)}`).join(' ');
const nameOf = (role: string) => `${titled(role)} persona: give it a name`;
const promptOf = (role: string) => `${titled(role)} persona: describe how it behaves`;
const gateOf = (role: string) => `Customise the ${role}'s persona?`;

test('each role is asked for a persona after its agent, the author first; Default skips name and prompt and leaves none', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({ [gateOf('reviewer')]: true, [nameOf('reviewer')]: ' Rex ', [promptOf('reviewer')]: 'Be strict about migrations.' });
  const out = join(dir, 'p1.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  const order = [gateOf('author'), nameOf('author'), promptOf('author'), 'Which account runs the reviewer?', gateOf('reviewer'), nameOf('reviewer'), promptOf('reviewer')];
  expect(asked.filter((q) => order.includes(q))).toEqual([gateOf('author'), 'Which account runs the reviewer?', gateOf('reviewer'), nameOf('reviewer'), promptOf('reviewer')]);
  expect(asked.indexOf('Which account runs the author?')).toBeLessThan(asked.indexOf(gateOf('author')));
  expect(asked.indexOf(gateOf('author'))).toBeLessThan(asked.indexOf('Which account runs the reviewer?'));
  const agents = JSON.parse(written[out]!).agents;
  expect(agents.author).not.toHaveProperty('persona');
  expect(agents.reviewer.persona).toEqual({ name: 'Rex', prompt: 'Be strict about migrations.' });
});

test('personas are asked under a shared identity too, and the config loads', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi({ 'GitHub profile for the author': 'gh', 'GitHub profile for the reviewer': 'gh', [gateOf('author')]: true, [nameOf('author')]: 'Ada' });
  const out = join(dir, 'p2.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  const user = JSON.parse(written[out]!);
  expect(user.agents.author.persona).toEqual({ name: 'Ada' });
  expect(loadConfig(defaults, user, providersWritten(written) as never).ok).toBe(true);
});

test('the four persona flags skip their questions and reach the file', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'p3.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'codex:m1', reviewer: 'claude:m2', authorPersonaName: 'Ada', authorPersonaPrompt: 'Terse.', reviewerPersonaName: 'Rex', reviewerPersonaPrompt: 'Strict.', out }, ui, deps);
  expect(asked.filter((q) => q.includes(' persona: '))).toEqual([]);
  const agents = JSON.parse(written[out]!).agents;
  expect(agents.author.persona).toEqual({ name: 'Ada', prompt: 'Terse.' });
  expect(agents.reviewer.persona).toEqual({ name: 'Rex', prompt: 'Strict.' });
});

test('a persona flag that is empty, over the limit or has a line break fails and names the flag', async () => {
  const bad: Record<string, string> = {
    authorPersonaName: '',
    reviewerPersonaName: 'x'.repeat(41),
    authorPersonaPrompt: 'x'.repeat(4001),
    reviewerPersonaPrompt: '  ',
  };
  const flag = (key: string) => `--${key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`;
  for (const [key, value] of Object.entries(bad)) {
    const { deps } = fakeDeps();
    await expect(runInit({ repo: ['A/b'], out: join(dir, 'p4.json'), yes: true, [key]: value }, quietUi().ui, deps)).rejects.toThrow(flag(key));
  }
  await expect(runInit({ repo: ['A/b'], out: join(dir, 'p4.json'), yes: true, authorPersonaName: 'a\nb' }, quietUi().ui, fakeDeps().deps)).rejects.toThrow('--author-persona-name');
});

test('an answer outside the limits is refused in the question', async () => {
  const { deps } = fakeDeps();
  const { ui } = quietUi({ [gateOf('author')]: true });
  const refused: Array<string | undefined> = [];
  await runInit({ repo: ['A/b'], out: join(dir, 'p5.json') }, { ...ui, text: async (o) => (o.message === nameOf('author') ? (refused.push(o.validate?.('x'.repeat(41)), o.validate?.('a\nb'), o.validate?.(''), o.validate?.('Ada')), 'Ada') : ui.text(o)) }, deps);
  expect(refused[0]).toBeDefined();
  expect(refused[1]).toBeDefined();
  expect(refused[2]).toBeUndefined(); // empty skips
  expect(refused[3]).toBeUndefined();
});

test('editing a config with personas starts from them, and the recap lists them', async () => {
  const persona = { name: 'Rex', prompt: 'Be strict.' };
  const withPersona = { ...existing, agents: { ...existing.agents, reviewer: { ...existing.agents.reviewer, persona } } };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(withPersona) });
  const { ui } = quietUi({ [gateOf('reviewer')]: true });
  const defaultsSeen: Record<string, string | undefined> = {};
  const notes: Record<string, string> = {};
  await withHome(() => runInit({}, { ...ui, text: async (o) => (defaultsSeen[o.message] = o.defaultValue, ui.text(o)), note: (m, t) => void (notes[t] = m) }, deps));
  expect(defaultsSeen[nameOf('reviewer')]).toBe('Rex');
  expect(defaultsSeen[promptOf('reviewer')]).toBe('Be strict.');
  expect(notes['This is what will be saved']).toContain('persona: Rex · Be strict.');
  const { providers: _, ...config } = withPersona;
  expect(JSON.parse(written[join(dir, 'home', 'engine.json')]!)).toEqual(config);
});

test('editing a persona: a dash clears the field, and clearing both leaves no persona', async () => {
  const withPersona = { ...existing, agents: { ...existing.agents, reviewer: { ...existing.agents.reviewer, persona: { name: 'Rex', prompt: 'Be strict.' } } } };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(withPersona) });
  const { ui } = quietUi({ [gateOf('reviewer')]: true, [nameOf('reviewer')]: '-', [promptOf('reviewer')]: '-' });
  await withHome(() => runInit({}, ui, deps));
  expect(JSON.parse(written[join(dir, 'home', 'engine.json')]!).agents.reviewer).not.toHaveProperty('persona');
});

test('editing a persona: Enter keeps it with its fields prefilled, saying no drops it', async () => {
  const withPersona = { ...existing, agents: { ...existing.agents, reviewer: { ...existing.agents.reviewer, persona: { name: 'Rex', prompt: 'Be strict.' } } } };
  for (const [answer, expected] of [[undefined, { name: 'Rex', prompt: 'Be strict.' }], [false, undefined]] as const) {
    const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(withPersona) });
    const { ui, asked } = quietUi(answer === undefined ? {} : { [gateOf('reviewer')]: answer });
    await withHome(() => runInit({}, ui, deps));
    expect(asked.includes(nameOf('reviewer'))).toBe(answer === undefined);
    expect(JSON.parse(written[join(dir, 'home', 'engine.json')]!).agents.reviewer.persona).toEqual(expected);
  }
});

test('adding a lead reviewer asks its identity, provider, model and persona, and writes it to agents', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({
    'Add a lead reviewer?': true,
    'GitHub profile for the lead reviewer': 'forge:tassadar-agent',
    'Which account runs the lead reviewer?': 'claude',
    'Model and effort: sonnet at high, change them?': [false, true],
    'Model for the lead reviewer': 'opus',
    [gateOf('lead reviewer')]: true,
    [nameOf('lead reviewer')]: 'Architect',
  });
  const out = join(dir, 'lead.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked).toContain('Add a lead reviewer?');
  expect(asked).toContain('GitHub profile for the lead reviewer');
  expect(asked).toContain('Which account runs the lead reviewer?');
  expect(asked).toContain('Model for the lead reviewer');

  const config = JSON.parse(written[out]!);
  expect(config.agents.leadReviewer).toEqual({
    profile: 'tassadar-agent',
    provider: 'claude',
    model: 'opus',
    effort: 'high',
    persona: { name: 'Architect' },
  });
  expect(loadConfig(defaults, config, providersWritten(written) as never).ok).toBe(true);
});

test('lead reviewer flag configures lead reviewer in unattended runs', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'lead-flag.json');
  await runInit({
    repo: ['A/b'],
    authorProfile: 'forge:artanis-agent',
    reviewerProfile: 'gh',
    author: 'codex:m1',
    reviewer: 'claude:m2',
    leadReviewer: 'claude:opus',
    leadReviewerProfile: 'gh',
    out,
    yes: true,
  }, ui, deps);
  const config = JSON.parse(written[out]!);
  expect(config.agents.leadReviewer).toEqual({
    profile: 'gh',
    provider: 'claude',
    model: 'opus',
    effort: 'high',
  });
  expect(loadConfig(defaults, config, providersWritten(written) as never).ok).toBe(true);
});

test('Enter says No to every optional extra and Yes to going on', async () => {
  const { deps } = fakeDeps();
  const { ui, asked } = quietUi();
  const initial: Record<string, boolean | undefined> = {};
  const spy: Ui = { ...ui, confirm: async (message, initialValue) => ((initial[message] = initialValue), ui.confirm(message, initialValue)) };
  await runInit({ repo: ['A/b'], out: join(dir, 'enter.json') }, spy, deps);
  expect(initial['Add another account?']).toBe(false);
  expect(initial['Add a lead reviewer?']).toBe(false);
  expect(initial[notNow]).toBe(true);
  expect(asked).not.toContain('Which agent CLI runs this account?'); // Enter on the first one added nothing
});

const changeMenu = 'Which part do you want to change?';

/** The Ui with an Esc the first time each of these questions is asked (once each), and a record of the starting point every question was shown with. */
function withEsc(base: Ui, escapeAt: string[]) {
  const pending = [...escapeAt];
  const starts: Record<string, unknown[]> = {};
  const gate = (message: string, start: unknown) => {
    (starts[message] ??= []).push(start);
    const at = pending.indexOf(message);
    if (at >= 0) {
      pending.splice(at, 1);
      throw new Back();
    }
  };
  const ui: Ui = {
    ...base,
    select: async (o) => (gate(o.message, o.initialValue), base.select(o)),
    confirm: async (m, i) => (gate(m, i), base.confirm(m, i)),
    text: async (o) => (gate(o.message, o.defaultValue), base.text(o)),
    multiselect: async (o) => (gate(o.message, o.initialValues), base.multiselect(o)),
  };
  return { ui, starts };
}

test('"Change an answer" at the recap is a menu of blocks: choosing one asks only its questions, from its answers, and the recap again', async () => {
  const { deps, written } = fakeDeps();
  const base = quietUi({ 'Save it?': ['change', 'save'], [changeMenu]: 'author', 'Model and effort: sonnet at high, change them?': true, 'Model for the author': ['opus', 'sonnet'], [notNow]: false });
  const { ui, starts } = withEsc(base.ui, []);
  const out = join(dir, 'change.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  const afterTheChoice = base.asked.slice(base.asked.indexOf(changeMenu) + 1);
  expect(afterTheChoice.slice(0, afterTheChoice.indexOf('Save it?') + 1)).toEqual([
    'GitHub profile for the author',
    'Which account runs the author?',
    'Model and effort: sonnet at high, change them?',
    'Model for the author',
    'Effort for the author',
    "Customise the author's persona?",
    'Turn failover on for the author? When it runs out of credits it moves to the steps you list, each an account and a model.',
    'Save it?', // only the author's questions, then the recap again
  ]);
  expect(starts['Model for the author']![1]).toBe('opus'); // the second time it starts from the first answer
  expect(base.asked.filter((q) => q === 'Save it?')).toHaveLength(2);
  expect(JSON.parse(written[out]!).agents.author.model).toBe('sonnet');
});

test('Esc goes back one question and shows it with its answer, across the edge of a block, and the config written is the one from the final answers', async () => {
  const { deps, written } = fakeDeps();
  const base = quietUi({ 'Which account runs the author?': 'claude', 'Which account runs the reviewer?': 'codex', [notNow]: false });
  // Esc at the first question of the reviewer's block goes to the last of the author's.
  const { ui, starts } = withEsc(base.ui, ['GitHub profile for the reviewer']);
  const out = join(dir, 'esc.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  const author = base.asked.filter((q) => q.includes('author'));
  const lastOfAuthor = "Turn failover on for the author? When it runs out of credits it moves to the steps you list, each an account and a model.";
  expect(author.filter((q) => q === lastOfAuthor)).toHaveLength(2); // asked again, nothing else of the author was
  expect(author.filter((q) => q === 'Which account runs the author?')).toHaveLength(1);
  expect(starts[lastOfAuthor]).toEqual([false, false]); // the second time it starts from the answer it had
  expect(JSON.parse(written[out]!).agents.reviewer.provider).toBe('codex');
});

test('Esc at the very first question leaves as Ctrl+C does, and nothing is written', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = withEsc(quietUi().ui, ['Add another account?']);
  await expect(runInit({ repo: ['A/b'], out: join(dir, 'first.json') }, ui, deps)).rejects.toBeInstanceOf(Cancelled);
  expect(written).toEqual({});
});

test('Ctrl+C at any question before Save leaves with nothing written', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi();
  const spy: Ui = { ...ui, select: async (o) => (o.message === 'Which account runs the reviewer?' ? Promise.reject(new Cancelled()) : ui.select(o)) };
  await expect(runInit({ repo: ['A/b'], out: join(dir, 'ctrlc.json') }, spy, deps)).rejects.toBeInstanceOf(Cancelled);
  expect(written).toEqual({});
});

test('Esc at the recap goes back to the last question', async () => {
  const { deps } = fakeDeps();
  const { ui, starts } = withEsc(quietUi({ [notNow]: false }).ui, ['Save it?']);
  await runInit({ repo: ['A/b'], out: join(dir, 'recap-esc.json') }, ui, deps);
  expect(starts['Add a lead reviewer?']).toEqual([false, false]);
});

test('going back across the repo listing or an added bot calls them zero more times', async () => {
  let listed = 0;
  let added = 0;
  const bots = [{ name: 'artanis-agent' }];
  const { deps } = fakeDeps({
    which: () => true,
    listRepos: () => ((listed += 1), { names: ['AshuLab/carrier'], hasMore: false }),
    forgeAgents: () => [...bots],
    forgeAdd: () => ((added += 1), bots.push({ name: 'new-agent' }), true),
  });
  const base = quietUi({ 'GitHub profile for the author': ['\0add', 'forge:new-agent'], 'Repos to watch': 'AshuLab/carrier', [notNow]: false });
  // Esc at the repos, then at the last question of the reviewer's block: both are before the listing and the bot
  const { ui } = withEsc(base.ui, ['Repos to watch', 'Add a lead reviewer?']);
  await runInit({ out: join(dir, 'zero.json') }, ui, deps);
  expect([listed, added]).toEqual([1, 1]);
});

test('two Escs back to the account and a new account: what depended on it is asked again, not answered from the journal', async () => {
  const { deps } = fakeDeps();
  const base = quietUi({ 'Which account runs the author?': ['claude', 'codex'], 'Model and effort: sonnet at high, change them?': true, 'Model for the author': 'opus', [notNow]: false });
  const { ui } = withEsc(base.ui, ['Model for the author', 'Model and effort: sonnet at high, change them?']);
  await runInit({ repo: ['A/b'], out: join(dir, 'gone.json') }, ui, deps);
  expect(base.asked.filter((q) => q === 'Which account runs the author?')).toHaveLength(2);
  expect(base.asked).toContain('Model and effort: gpt-test at high, change them?'); // the codex account has its own question
});

test('Esc at "Start Carrier now?" after the save counts as no, like Ctrl+C', async () => {
  const { deps } = fakeDeps();
  const { ui } = quietUi();
  const spy: Ui = { ...ui, confirm: async (m, i) => (m === notNow ? Promise.reject(new Back()) : ui.confirm(m, i)) };
  const done = await runInit({ repo: ['A/b'], out: join(dir, 'late-esc.json') }, spy, deps);
  expect(done.start).toBe(false);
});

test('an existing failover is kept only when the person says so; saying no asks for it again', async () => {
  const withFailover = { ...existing, failover: { triggers: ['usage_limit'], roles: { author: [{ provider: 'codex', model: 'gpt-test' }] } } };
  const keep = 'Keep the failover you have? author: codex gpt-test';
  const kept = fakeDeps({ exists: () => true, readConfig: asFiles(withFailover) });
  await withHome(() => runInit({}, quietUi({ [notNow]: false }).ui, kept.deps));
  expect(JSON.parse(kept.written[join(dir, 'home', 'engine.json')]!).failover.roles.author).toEqual([{ provider: 'codex', model: 'gpt-test' }]);
  const redone = fakeDeps({ exists: () => true, readConfig: asFiles(withFailover) });
  const { ui, asked } = quietUi({ [keep]: false, [notNow]: false });
  await withHome(() => runInit({}, ui, redone.deps));
  expect(asked.some((q) => q.startsWith('Turn failover on for the author'))).toBe(true);
  expect(JSON.parse(redone.written[join(dir, 'home', 'engine.json')]!).failover).toEqual({ triggers: ['usage_limit'] }); // asked again and declined: the steps go, the file's triggers stay
});

test('every wait on the machine or GitHub shows a loading line', async () => {
  const waits: string[] = [];
  const { ui } = quietUi({ [notNow]: false });
  const spy: Ui = { ...ui, busy: (message, work) => (waits.push(message), work()) };
  const { deps } = fakeDeps({ listRepos: () => ({ names: ['AshuLab/carrier'], hasMore: false }) });
  await runInit({ out: join(dir, 'busy.json') }, spy, deps);
  expect(waits).toEqual(['Looking at this Mac…', 'Reading your GitHub repos…', 'Asking GitHub which epics are ready…']);
});

test('asking Antigravity which models it has shows a loading line, once, even when Esc runs the block again', async () => {
  const waits: string[] = [];
  let calls = 0;
  const { ui } = quietUi({ 'Which account runs the author?': 'agy', [notNow]: false });
  const spy: Ui = { ...withEsc(ui, ["Customise the author's persona?"]).ui, busy: (message, work) => (waits.push(message), work()) };
  const { deps } = fakeDeps({ machine: fakeMachine({ resolveBinary: (name) => `/opt/bin/${name}` }), agyModels: () => (calls++, [{ value: 'gemini-4-hydrogen-high', label: 'gemini-4-hydrogen-high' }]) });
  await runInit({ repo: ['A/b'], out: join(dir, 'busy-agy.json') }, spy, deps);
  expect(waits.filter((w) => w.startsWith('Asking Antigravity'))).toHaveLength(1);
  expect(calls).toBe(1);
});

test('the profile step is explained before it is asked, unless both profiles came as flags', async () => {
  const noteFor = async (flags: Parameters<typeof runInit>[0]) => {
    const { ui, notes } = quietUi({ [notNow]: false });
    await runInit({ repo: ['A/b'], ...flags }, ui, fakeDeps().deps);
    return notes.find((n) => n.title === 'GitHub profiles')?.message;
  };
  const note = await noteFor({ out: join(dir, 'ident-1.json') });
  expect(note).toContain('Agent Forge bot');
  expect(note).toContain('(diego)'); // the gh login shown is the one found
  expect(await noteFor({ out: join(dir, 'ident-2.json'), authorProfile: 'gh', reviewerProfile: 'forge:artanis-agent' })).toBeUndefined();
});

test('the orchestrator is asked before the author and the reviewer, and its answer is the one written', async () => {
  const { deps, written } = fakeDeps();
  const order: string[] = [];
  const { ui } = quietUi({ 'GitHub profile for the orchestrator': 'gh' });
  const spy: Ui = { ...ui, select: async (o) => (order.push(o.message), ui.select(o)) };
  const out = join(dir, 'orch.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(order.filter((m) => m.startsWith('GitHub profile for'))).toEqual(['GitHub profile for the orchestrator', 'GitHub profile for the author', 'GitHub profile for the reviewer']);
  const config = JSON.parse(written[out]!);
  expect(config.orchestratorProfile).toBe('gh');
  expect(config.profiles.gh).toEqual({ kind: 'gh' });
  expect(config.agents.author.profile).toBe('artanis-agent'); // the orchestrator's answer does not move the author's
});

test('editing a config starts the orchestrator from the file, and an unattended run makes it the author', async () => {
  const { deps } = fakeDeps({ exists: () => true, readConfig: asFiles(existing) });
  const seen: (string | undefined)[] = [];
  const { ui } = quietUi({ [existingKey]: 'edit' });
  const spy: Ui = { ...ui, select: async (o) => (o.message === 'GitHub profile for the orchestrator' && seen.push(String(o.initialValue)), ui.select(o)) };
  await withHome(() => runInit({}, spy, deps));
  expect(seen).toEqual(['forge:tassadar-agent']);

  const { deps: unattended, written } = fakeDeps();
  const out = join(dir, 'q.json');
  await runInit({ repo: ['A/b'], authorProfile: 'gh', reviewerProfile: 'forge:artanis-agent', author: 'claude:m1', reviewer: 'codex:m2', out, yes: true }, quietUi().ui, unattended);
  expect(JSON.parse(written[out]!).orchestratorProfile).toBe('gh');
});

test('with both profile flags an edit keeps the file\'s own orchestrator, and the recap shows it', async () => {
  const file = {
    ...existing,
    profiles: { 'artanis-agent': { kind: 'forge', agent: 'artanis-agent' }, 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' }, gh: { kind: 'gh' } },
    orchestratorProfile: 'artanis-agent',
    agents: { author: { profile: 'gh', provider: 'claude', model: 'opus' }, reviewer: { profile: 'tassadar-agent', provider: 'codex', model: 'gpt-test' } },
  };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(file) });
  const { ui } = quietUi({ [existingKey]: 'edit', [notNow]: false });
  const notes: Record<string, string> = {};
  await withHome(() => runInit({ authorProfile: 'gh', reviewerProfile: 'forge:tassadar-agent', author: 'claude:m1', reviewer: 'codex:m2' }, { ...ui, note: (m, t) => void (notes[t] = m) }, deps));
  expect(notes['This is what will be saved']).toContain('Orchestrator  artanis-agent');
  expect(JSON.parse(written[join(dir, 'home', 'engine.json')]!).orchestratorProfile).toBe('artanis-agent');
});

test('with a single profile the orchestrator answers itself and says so', async () => {
  const { deps, written } = fakeDeps({ forgeAgents: () => [], which: (tool) => tool !== 'agent-forge' });
  const { ui } = quietUi();
  const notes: { title?: string; message: string }[] = [];
  const out = join(dir, 'lone.json');
  await runInit({ repo: ['A/b'], out }, { ...ui, note: (message, title) => void notes.push({ title, message }) }, deps);
  expect(notes.find((n) => n.title === 'GitHub profile for the orchestrator')?.message).toContain('the only profile there is');
  expect(JSON.parse(written[out]!).orchestratorProfile).toBe('gh');
});

// the real writing code, in a scratch Carrier folder and with no socket
const viaModule = () => ({ ...fakeDeps().deps, writeConfig: realDeps.writeConfig });

test('the two files are written by the config writing module: --out chooses engine.json, providers.json stays in the Carrier folder and no temporary file is left', async () => {
  const folder = join(dir, 'module', 'carrier');
  const out = join(dir, 'module', 'elsewhere', 'engine.json');
  await runInit({ repo: ['A/b'], out, yes: true }, quietUi().ui, viaModule(), folder);
  expect(Object.keys(JSON.parse(readFileSync(out, 'utf8')))).toContain('repos');
  expect(JSON.parse(readFileSync(join(folder, 'providers.json'), 'utf8')).providers).toHaveProperty('claude');
  expect(readFileSync(out, 'utf8')).toMatch(/\n$/);
  expect(readdirSync(folder)).toEqual(['providers.json']);
  expect(readdirSync(join(dir, 'module', 'elsewhere'))).toEqual(['engine.json']);
});

test('a providers.json the writing module refuses is left as it was, the refusal\'s words are the error and engine.json is not written', async () => {
  const folder = join(dir, 'refused', 'carrier');
  mkdirSync(folder, { recursive: true });
  writeFileSync(join(folder, 'providers.json'), '{ not json');
  const out = join(folder, 'engine.json');
  await expect(runInit({ repo: ['A/b'], out, yes: true }, quietUi().ui, viaModule(), folder)).rejects.toThrow(`${join(folder, 'providers.json')} is not valid JSON, so it was not changed`);
  expect(readFileSync(join(folder, 'providers.json'), 'utf8')).toBe('{ not json');
  expect(readdirSync(folder)).toEqual(['providers.json']);
});

// The order, the failover rule, the accounts kept and the wording, all through `runInit`.

test('with every default accepted the questions come in the order: accounts, orchestrator, author, reviewer, extra reviewers, lead reviewer, repos, recap', async () => {
  const { ui, asked, notes } = quietUi();
  const { deps } = fakeDeps({ listRepos: () => ({ names: ['AshuLab/carrier'], hasMore: false }) });
  await runInit({ out: join(dir, 'order.json') }, ui, deps);
  expect(notes.map((n) => n.title).filter((t) => t === 'Found on this Mac' || t === 'AI accounts')).toEqual(['Found on this Mac', 'AI accounts']);
  expect(asked.filter((m) => !m.startsWith('outro') && !m.startsWith('checks:'))).toEqual([
    'Add another account?',
    'GitHub profile for the orchestrator',
    'GitHub profile for the author',
    'Which account runs the author?',
    'Model and effort: sonnet at high, change them?',
    "Customise the author's persona?",
    'Turn failover on for the author? When it runs out of credits it moves to the steps you list, each an account and a model.',
    'GitHub profile for the reviewer',
    'Which account runs the reviewer?',
    'Model and effort: gpt-test at high, change them?',
    "Customise the reviewer's persona?",
    'Turn failover on for the reviewer? When it runs out of credits it moves to the steps you list, each an account and a model.',
    'Add another reviewer?',
    'Add a lead reviewer?',
    'Repos to watch',
    'Save it?',
    'Start Carrier now?',
  ]);
});

test('failover needs two accounts: with one the block says so and asks nothing, and the steps chosen with two are written under failover.roles', async () => {
  const one = fakeDeps({ machine: fakeMachine({ resolveBinary: (name) => {
      if (name === 'claude') return '/opt/bin/claude';
      throw new Error('missing');
    } }) });
  const alone = quietUi({ [moreKey]: [true, false], [nameKey]: 'Seguridad', 'Add a lead reviewer?': true });
  await runInit({ repo: ['A/b'], out: join(dir, 'one.json') }, withEsc(alone.ui, ['Add a lead reviewer?']).ui, one.deps);
  expect(alone.asked.some((m) => m.startsWith('Turn failover on'))).toBe(false);
  // once for the whole run, whatever the number of roles and the Esc that ran the blocks again
  expect(alone.notes.filter((n) => n.title === 'Failover').map((n) => n.message)).toEqual(['Failover needs a second account, so no role has one.']);

  const two = fakeDeps();
  const out = join(dir, 'two.json');
  const { ui } = quietUi({ 'Turn failover on for the author? When it runs out of credits it moves to the steps you list, each an account and a model.': true, 'Failover for the author: which account goes first?': 'codex', 'Failover for the author: which account goes second?': '\0done' });
  await runInit({ repo: ['A/b'], out }, ui, two.deps);
  expect(JSON.parse(two.written[out]!).failover.roles.author).toEqual([{ provider: 'codex', model: 'gpt-test' }]);
});

test('every account providers.json already held is still there after --yes, "Start over", an edit and a new file', async () => {
  const held = { claude: { harness: 'claude' }, 'claude-work': { harness: 'claude', configDir: '~/.claude-work', model: 'opus' } };
  const engineFile = { ...existing, providers: undefined, agents: { ...existing.agents, reviewer: { profile: 'gh', provider: 'claude-work', model: 'opus' } } }; // accounts are not engine.json's, and the file names only accounts the file of accounts holds
  const files = (path: string) => (path.endsWith('providers.json') ? { providers: held } : JSON.parse(JSON.stringify(engineFile)));
  const run = async (flags: Parameters<typeof runInit>[0], answers: Record<string, string | boolean> = {}) => {
    const { deps, written } = fakeDeps({ exists: (path) => path.endsWith('providers.json') || path.endsWith('engine.json'), readConfig: files });
    const { ui, notes } = quietUi({ [notNow]: false, ...answers });
    await withHome(() => runInit({ repo: ['A/b'], ...flags }, ui, deps));
    return { accounts: providersWritten(written, join(dir, 'home')), notes };
  };
  for (const accounts of [
    (await run({ yes: true, out: join(dir, 'held-yes.json') })).accounts,
    (await run({ out: join(dir, 'held-new.json') })).accounts,
    (await run({}, { [existingKey]: 'fresh' })).accounts,
    (await run({}, { [existingKey]: 'edit' })).accounts,
  ]) {
    expect(accounts.claude).toEqual({ harness: 'claude' });
    expect(accounts['claude-work']).toEqual(held['claude-work']); // its own folder and settings
    expect(accounts.codex).toEqual({ harness: 'codex' }); // the harness found with no account is added under its name
  }
  const { notes } = await run({ out: join(dir, 'held-note.json') });
  const text = notes.map((n) => n.message).join('\n');
  expect(text).toContain('kept as they are');
  expect(text).not.toMatch(/replace/i);
});

test('a config written with every default holds high for Claude and Codex and no effort for Antigravity', async () => {
  const { deps, written } = fakeDeps({ machine: fakeMachine({ resolveBinary: (name) => `/opt/bin/${name}` }), agyModels: () => [{ value: 'gemini-4-hydrogen-high', label: 'gemini-4-hydrogen-high' }] });
  const out = join(dir, 'agy.json');
  const { ui } = quietUi({ 'Which account runs the author?': 'agy', 'Which account runs the reviewer?': 'claude', 'GitHub profile for the author': 'forge:artanis-agent' });
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(JSON.parse(written[out]!).agents).toEqual({
    author: { profile: 'artanis-agent', provider: 'agy', model: 'gemini-4-hydrogen-high' },
    reviewer: { profile: 'tassadar-agent', provider: 'claude', model: 'sonnet', effort: 'high' },
  });
});

test('no message, note, option or warning of a full run says "identity" or "fallback": the words are profile and failover', async () => {
  const spoken: string[] = [];
  const { ui, notes } = quietUi({
    'Add another account?': [true, false],
    'Which agent CLI runs this account?': 'claude',
    'Which account runs the author?': 'claude',
    'Which account runs the reviewer?': 'codex',
    'Model and effort: sonnet at high, change them?': true,
    "Customise the author's persona?": true,
    'Author persona: give it a name': 'Rex',
    'Author persona: describe how it behaves': 'Be rigorous.',
    'Turn failover on for the author? When it runs out of credits it moves to the steps you list, each an account and a model.': true,
    'Failover for the author: which account goes first?': 'codex',
    'Failover for the author: which account goes second?': '\0done',
    'Add a lead reviewer?': true,
    'Save it?': ['change', 'save'],
    [notNow]: false,
  });
  const record = (...parts: (string | undefined)[]) => void spoken.push(...parts.filter((p): p is string => p !== undefined));
  const spy: Ui = {
    ...ui,
    warn: (m) => (record(m), ui.warn(m)),
    select: async (o) => (record(o.message, ...o.options.flatMap((x) => [x.label, x.hint])), ui.select(o)),
    text: async (o) => (record(o.message, o.placeholder), ui.text(o)),
    confirm: async (m, i) => (record(m), ui.confirm(m, i)),
    multiselect: async (o) => (record(o.message, ...Object.values(o.options).flat().flatMap((x) => [x.label, x.hint])), ui.multiselect(o)),
    check: (c) => (record(c.name), ui.check(c)),
  };
  const { deps } = fakeDeps({ listRepos: () => ({ names: ['AshuLab/carrier'], hasMore: false }), configFolders: () => ['/home/x/.claude-2'] });
  await runInit({ out: join(dir, 'words.json') }, spy, deps);
  record(...notes.flatMap((n) => [n.title, n.message]));
  expect(spoken.length).toBeGreaterThan(40);
  expect(spoken.filter((m) => /identit|fallback/i.test(stripVTControlCharacters(m)))).toEqual([]);
});

// Extra reviewers: the loop, the cap, the name and the type, edit mode and the written file.

const moreKey = 'Add another reviewer?';
const nameKey = 'What is this extra reviewer called?';
const typeKey = 'What does it look at? A type, like general, security or ux';
const flagged: InitFlags = { repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'claude:m1', reviewer: 'codex:m2' };
const inTheWords = (texts: string[]) => texts.filter((text) => /reviewer[- ]?[234]\b/i.test(stripVTControlCharacters(text)));

test('"Add another reviewer?" opens a block that asks the name and then the type before the rest, is not asked after the third, and the lead comes after all of them', async () => {
  const { ui, asked, notes } = quietUi({ [moreKey]: [true, true, true], [nameKey]: ['Seguridad API', 'Usabilidad', '123'], [typeKey]: ['security', 'ux'], 'Add a lead reviewer?': true });
  const { deps, written } = fakeDeps();
  const out = join(dir, 'extras-loop.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked.filter((m) => m === moreKey)).toHaveLength(3);
  expect(notes.map((n) => n.title).filter((t) => ['Author', 'Reviewer', 'Seguridad API', 'Usabilidad', '123', 'Lead reviewer'].includes(t ?? ''))).toEqual(['Author', 'Reviewer', 'Seguridad API', 'Usabilidad', '123', 'Lead reviewer']);
  const first = asked.indexOf(moreKey);
  expect(asked.slice(first, first + 5)).toEqual([moreKey, nameKey, typeKey, 'GitHub profile for the extra reviewer', 'Which account runs the extra reviewer?']);
  expect(asked.lastIndexOf('Which account runs the extra reviewer?')).toBeLessThan(asked.indexOf('Add a lead reviewer?'));
  const config = JSON.parse(written[out]!);
  expect(Object.keys(config.agents.extraReviewers)).toEqual(['seguridad-api', 'usabilidad', 'r-123']); // the keys come from the names, in the order they were given
  expect(config.agents.extraReviewers['seguridad-api']).toMatchObject({ type: 'security', name: 'Seguridad API', provider: 'claude', model: 'sonnet' });
  expect(config.agents.extraReviewers['seguridad-api']).not.toHaveProperty('failover');
  expect(config.agents.extraReviewers.usabilidad).toMatchObject({ type: 'ux', name: 'Usabilidad' });
  expect(config.agents.extraReviewers['r-123']).toMatchObject({ type: 'general', name: '123' }); // Enter at the type
  expect(config.agents).toHaveProperty('leadReviewer');
  expect(loadConfig(defaults, config, providersWritten(written) as never).ok).toBe(true);
  expect(inTheWords([...asked, ...notes.flatMap((n) => [n.title ?? '', n.message])])).toEqual([]);
});

test('the name has no suggestion and a blank answer asks again, and so does one that another reviewer has, without regard to case', async () => {
  const { ui, asked } = quietUi({ [moreKey]: [true, true, false], [nameKey]: ['', '   ', 'Seguridad', 'SEGURIDAD', 'Usabilidad'] });
  const seen: unknown[] = [];
  const spy: Ui = { ...ui, text: async (o) => (o.message === nameKey && seen.push(o.defaultValue), ui.text(o)) };
  const { deps, written } = fakeDeps();
  const out = join(dir, 'extras-name.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(asked.filter((m) => m === nameKey)).toHaveLength(5);
  expect(seen).toEqual([undefined, undefined, undefined, undefined, undefined]);
  expect(asked.filter((m) => m.startsWith('warn:'))).toEqual(['warn:a name is required: try another name', 'warn:a name is required: try another name', 'warn:another extra reviewer already has that name: try another name']);
  expect(Object.keys(JSON.parse(written[out]!).agents.extraReviewers)).toEqual(['seguridad', 'usabilidad']);
});

test('the type starts on general, and a type that is not a slug asks again', async () => {
  const { ui, asked } = quietUi({ [moreKey]: [true, false], [nameKey]: 'Seguridad', [typeKey]: ['Not A Slug', 'security'] });
  const starts: unknown[] = [];
  const spy: Ui = { ...ui, text: async (o) => (o.message === typeKey && starts.push(o.defaultValue), ui.text(o)) };
  const { deps, written } = fakeDeps();
  const out = join(dir, 'extras-type.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(starts).toEqual(['general', 'general']);
  expect(asked.filter((m) => m.startsWith('warn:'))).toHaveLength(1);
  expect(JSON.parse(written[out]!).agents.extraReviewers.seguridad.type).toBe('security');
});

test('names that give the same key get -2, and one that is a role\'s word is not the key', async () => {
  const { ui } = quietUi({ [moreKey]: [true, true, true], [nameKey]: ['A B', 'A-B', 'Lead'] });
  const { deps, written } = fakeDeps();
  const out = join(dir, 'extras-keys.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(Object.keys(JSON.parse(written[out]!).agents.extraReviewers)).toEqual(['a-b', 'a-b-2', 'lead-2']);
});

test('Enter at "Add another reviewer?" is no, and no extraReviewers key is written', async () => {
  const { ui, asked } = quietUi();
  const { deps, written } = fakeDeps();
  const out = join(dir, 'extras-none.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked.filter((m) => m === moreKey)).toHaveLength(1);
  expect(JSON.parse(written[out]!).agents).not.toHaveProperty('extraReviewers');
});

test('the recap lists each extra reviewer by its name and type', async () => {
  const { ui, notes } = quietUi({ [moreKey]: [true, true, false], [nameKey]: ['Seguridad API', 'Usabilidad'], [typeKey]: ['security', 'ux'] });
  await runInit({ repo: ['A/b'], out: join(dir, 'extras-recap.json') }, ui, fakeDeps().deps);
  const recap = notes.find((n) => n.title === 'This is what will be saved')!.message;
  expect(recap).toMatch(/\nExtra {9}Seguridad API · security · .* · claude .*\nExtra {9}Usabilidad · ux · /);
  expect(inTheWords([recap])).toEqual([]);
});

test('an extra with its own failover steps writes them, and one without writes no failover key', async () => {
  const failoverKey = 'Turn failover on for the extra reviewer? When it runs out of credits it moves to the steps you list, each an account and a model.';
  const { ui } = quietUi({ [moreKey]: [true, true, false], [nameKey]: ['Seguridad', 'Usabilidad'], [failoverKey]: [true, false], 'Failover for the extra reviewer: which account goes first?': 'codex', 'Failover for the extra reviewer: which account goes second?': '\0done' });
  const { deps, written } = fakeDeps();
  const out = join(dir, 'extras-failover.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  const extras = JSON.parse(written[out]!).agents.extraReviewers;
  expect(extras.seguridad.failover).toEqual([{ provider: 'codex', model: 'gpt-test' }]);
  expect(extras.usabilidad).not.toHaveProperty('failover');
});

test('under --yes there is no extra reviewer: no flag creates one yet, and nothing is asked', async () => {
  const none = fakeDeps();
  const { ui, asked } = quietUi();
  await runInit({ ...flagged, yes: true, out: join(dir, 'extras-yes-none.json') }, ui, none.deps);
  expect(JSON.parse(none.written[join(dir, 'extras-yes-none.json')]!).agents).not.toHaveProperty('extraReviewers');
  expect(asked.filter((m) => !m.startsWith('outro') && !m.startsWith('checks:'))).toEqual([]);
});

const withExtras = {
  ...existing,
  agents: {
    ...existing.agents,
    extraReviewers: {
      'seguridad-api': { type: 'security', name: 'Seguridad API', profile: 'gh', provider: 'claude', model: 'opus', effort: 'low', skills: { review: { review: 'mine' } }, failover: [{ provider: 'codex' }] },
      usabilidad: { type: 'ux', name: 'Usabilidad', profile: 'tassadar-agent', provider: 'codex', model: 'gpt-x', skills: { review: { publish: null } } },
    },
  },
};
const editWith = async (file: object, answers: Record<string, boolean | string | (boolean | string)[]> = {}) => {
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(file as Record<string, unknown>) });
  const base = quietUi({ [existingKey]: 'edit', [notNow]: false, ...answers });
  const starts: Record<string, unknown> = {};
  const spy: Ui = {
    ...base.ui,
    text: async (o) => ((starts[o.message] ??= o.defaultValue), base.ui.text(o)),
    confirm: async (m, i) => ((starts[m] ??= i), base.ui.confirm(m, i)),
  };
  await withHome(() => runInit({}, spy, deps));
  return { agents: JSON.parse(written[join(dir, 'home', 'engine.json')]!).agents, asked: base.asked, starts };
};

test('in edit mode each extra reviewer of the map is walked in its order from its name and type, and the file keeps its key, skills and failover', async () => {
  const { agents, asked, starts } = await editWith(withExtras);
  expect(asked.filter((m) => /^(Keep .*\?|Add .*reviewer\?)$/.test(m) || m === nameKey || m === typeKey)).toEqual(['Keep Seguridad API?', nameKey, typeKey, 'Keep Usabilidad?', nameKey, typeKey, moreKey, 'Add a lead reviewer?']);
  expect(starts['Keep Seguridad API?']).toBe(true);
  expect(starts[moreKey]).toBe(false);
  expect(agents.extraReviewers).toEqual(withExtras.agents.extraReviewers);
  expect(Object.keys(agents.extraReviewers)).toEqual(['seguridad-api', 'usabilidad']);
});

test('in edit mode the name and type start from the file\'s, and a new name keeps the key', async () => {
  const { agents, starts } = await editWith(withExtras, { [nameKey]: ['Seguridad Web', 'Usabilidad'], [typeKey]: ['appsec', 'ux'] });
  expect(starts[nameKey]).toBe('Seguridad API');
  expect(starts[typeKey]).toBe('security');
  expect(agents.extraReviewers['seguridad-api']).toMatchObject({ name: 'Seguridad Web', type: 'appsec', skills: { review: { review: 'mine' } } });
  expect(Object.keys(agents.extraReviewers)).toEqual(['seguridad-api', 'usabilidad']);
});

test('in edit mode a No drops that extra and the ones after it, and none left removes the key', async () => {
  expect((await editWith(withExtras, { 'Keep Usabilidad?': false })).agents.extraReviewers).toEqual({ 'seguridad-api': withExtras.agents.extraReviewers['seguridad-api'] });
  expect((await editWith(withExtras, { 'Keep Seguridad API?': false })).agents).not.toHaveProperty('extraReviewers');
});

test('an edit of a file with no extras asks "Add another reviewer?" on no and writes none', async () => {
  const { agents, asked } = await editWith(existing);
  expect(asked).toContain(moreKey);
  expect(agents).not.toHaveProperty('extraReviewers');
});

test('a file whose extraReviewers is a list is not edited: the first error names the map, and the wizard asks what to do and writes nothing', async () => {
  const list = { ...existing, agents: { ...existing.agents, extraReviewers: [{ profile: 'gh', provider: 'claude', model: 'opus' }] } };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(list) });
  const { ui, asked } = quietUi({ [existingKey]: 'edit', [notNow]: false });
  const options: string[] = [];
  const spy: Ui = { ...ui, select: async (o) => (options.push(...o.options.map((option) => option.value)), ui.select(o)) };
  await withHome(() => runInit({}, spy, deps).catch((error) => expect(error).toBeInstanceOf(Cancelled))); // the default answer leaves it
  expect(asked.find((m) => m.startsWith('warn:'))).toMatch(/does not validate, first error: agents\.extraReviewers: must be a map from a key to a reviewer, not a list/);
  expect(asked).toContain('What do you want to do with it?');
  expect(options.slice(-3)).toEqual(['fresh', 'elsewhere', 'cancel']);
  expect(written).toEqual({});
});

test('Esc back to an extra reviewer\'s name, changing it, keeps the answers given to the block\'s other questions as the starting points', async () => {
  const model = 'Model and effort: gpt-test at high, change them?';
  const { ui, asked } = quietUi({ [moreKey]: [true, false], [nameKey]: ['Seguridad', 'Seguridad Web'], [typeKey]: 'security', 'Which account runs the extra reviewer?': 'codex', "Customise the extra reviewer's persona?": true, 'Extra Reviewer persona: give it a name': 'Sentinel' });
  // Esc, in this order: at the lead question, then at each question that comes up from the end of the block back to the type, which goes back to the name.
  const backs = ['Add a lead reviewer?', moreKey, 'Turn failover on for the extra reviewer', 'Extra Reviewer persona: describe', 'Extra Reviewer persona: give it a name', "Customise the extra reviewer's persona?", 'Model and effort', 'Which account runs the extra reviewer?', 'GitHub profile for the extra reviewer', typeKey];
  const starts: Record<string, unknown[]> = {};
  let next = 0;
  const gate = (message: string, start: unknown) => {
    (starts[message] ??= []).push(start);
    if (message.startsWith(backs[next] ?? '\0')) {
      next++;
      throw new Back();
    }
  };
  const spy: Ui = {
    ...ui,
    select: async (o) => (gate(o.message, o.initialValue), ui.select(o)),
    confirm: async (m, i) => (gate(m, i), ui.confirm(m, i)),
    text: async (o) => (gate(o.message, o.defaultValue), ui.text(o)),
  };
  const { deps, written } = fakeDeps();
  const out = join(dir, 'extras-rename.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(next).toBe(backs.length);
  expect(starts[nameKey]).toEqual([undefined, 'Seguridad']); // the name starts from the one before, and nothing is suggested the first time
  expect(starts[typeKey]!.at(-1)).toBe('security');
  expect(starts['Which account runs the extra reviewer?']!.at(-1)).toBe('codex');
  expect(starts["Customise the extra reviewer's persona?"]!.at(-1)).toBe(true);
  expect(starts['Extra Reviewer persona: give it a name']!.at(-1)).toBe('Sentinel');
  expect(asked.filter((m) => m === model).length).toBeGreaterThan(1);
  const extras = JSON.parse(written[out]!).agents.extraReviewers;
  expect(Object.keys(extras)).toEqual(['seguridad-web']);
  expect(extras['seguridad-web']).toMatchObject({ name: 'Seguridad Web', type: 'security', provider: 'codex', persona: { name: 'Sentinel' } });
});

test('the recap\'s "Change an answer" lists each extra reviewer by its name and the next one to add, and a jump to one asks only its questions', async () => {
  const { deps, written } = fakeDeps();
  const base = quietUi({ [moreKey]: [true, false], [nameKey]: ['Seguridad', 'Seguridad Web'], 'Save it?': ['change', 'save'], [changeMenu]: 'extra-1', [notNow]: false });
  const labels: string[] = [];
  const spy: Ui = { ...base.ui, select: async (o) => (o.message === changeMenu && labels.push(...o.options.map((option) => option.label)), base.ui.select(o)) };
  const out = join(dir, 'extras-jump.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(labels).toEqual(['AI accounts', 'Orchestrator GitHub profile', 'Author', 'Reviewer', 'Seguridad', 'Extra reviewer', 'Lead reviewer', 'Repos to watch']);
  expect(base.asked.filter((m) => m === nameKey)).toHaveLength(2);
  expect(base.asked.filter((m) => m === 'GitHub profile for the author')).toHaveLength(1); // the author's block was not asked again
  expect(Object.keys(JSON.parse(written[out]!).agents.extraReviewers)).toEqual(['seguridad-web']);
});

test('--yes with a lead-reviewer flag alone, even one that is not --lead-reviewer, creates the lead reviewer', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi();
  const out = join(dir, 'lead-effort-only.json');
  await runInit({ repo: ['A/b'], leadReviewerEffort: 'xhigh', out, yes: true }, ui, deps);
  expect(JSON.parse(written[out]!).agents.leadReviewer).toMatchObject({ effort: 'xhigh' });
});

test('Esc at "Which part do you want to change?" goes back to "Save it?" and drops no answer', async () => {
  const { deps, written } = fakeDeps();
  const base = quietUi({ 'Save it?': ['change', 'save'], [notNow]: false });
  const { ui } = withEsc(base.ui, [changeMenu]);
  const out = join(dir, 'menu-esc.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(base.asked.filter((q) => q === 'Save it?')).toHaveLength(2); // the menu, Esc, and the recap's own question again
  expect(base.asked.filter((q) => q === 'Add a lead reviewer?')).toHaveLength(1); // the last answer was not dropped and asked again
  expect(JSON.parse(written[out]!).agents.reviewer.provider).toBe('codex');
});

test('Esc at the first question of a block the recap jumped to returns to the recap, with the block as it was', async () => {
  const { deps, written } = fakeDeps();
  const base = quietUi({ 'Save it?': ['change', 'save'], [changeMenu]: 'reviewer', [notNow]: false });
  let jumped = false;
  let escaped = false;
  const ui: Ui = {
    ...base.ui,
    select: async (o) => {
      if (o.message === changeMenu) jumped = true;
      if (jumped && !escaped && o.message === 'GitHub profile for the reviewer') {
        escaped = true;
        throw new Back();
      }
      return base.ui.select(o);
    },
  };
  const out = join(dir, 'jump-esc.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(escaped).toBe(true);
  expect(base.asked.filter((q) => q === 'Save it?')).toHaveLength(2); // back at the recap, not in the author's block
  expect(base.asked.filter((q) => q.startsWith('Turn failover on for the author'))).toHaveLength(1);
  expect(base.asked.filter((q) => q === 'GitHub profile for the reviewer')).toHaveLength(1); // the jump was abandoned, not asked on
  expect(JSON.parse(written[out]!).agents.reviewer.model).toBe('gpt-test');
});

test('the intro says how to go back, leave and when anything is written, and "Start over" names what it drops', async () => {
  const { deps } = fakeDeps({ exists: () => true, readConfig: asFiles(existing) });
  const spied: { message: string; hint?: string }[][] = [];
  const base = quietUi({ [notNow]: false });
  const { ui, notes } = base;
  const spy: Ui = { ...ui, select: async (o) => (spied.push(o.options as never), ui.select(o)) };
  await withHome(() => runInit({}, spy, deps));
  expect(notes.find((n) => n.title === 'What this does')!.message).toContain('Esc goes back one question, Ctrl+C leaves, and nothing is written until you save.');
  const hint = spied[0]!.find((o) => (o as { value?: string }).value === 'fresh')!.hint!;
  for (const dropped of ['limits', 'labels', 'skills', 'per-repo overrides', 'extra reviewers', 'keeps your accounts']) expect(hint).toContain(dropped);
});
