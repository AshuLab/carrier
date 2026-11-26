import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { stripVTControlCharacters } from 'node:util';
import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../config/load.ts';
import { Cancelled, type Ui } from '../prompts/types.ts';
import { realDeps } from './deps.ts';
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

test('"Change an answer" at the recap asks again from the same answers, and the second recap is what is written', async () => {
  const { deps, written } = fakeDeps();
  const base = quietUi({ 'Save it?': ['change', 'save'], 'Model and effort: sonnet at high, change them?': true, 'Model and effort: opus at high, change them?': true, 'Model for the author': ['opus', 'sonnet'], [notNow]: false });
  const modelDefaults: (string | undefined)[] = [];
  const spy: Ui = { ...base.ui, select: async (o) => (o.message === 'Model for the author' && modelDefaults.push(o.initialValue), base.ui.select(o)) };
  const out = join(dir, 'change.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(modelDefaults).toEqual(['sonnet', 'opus']); // the second time it starts from the first answer
  expect(base.asked.filter((q) => q === 'Save it?')).toHaveLength(2);
  expect(JSON.parse(written[out]!).agents.author.model).toBe('sonnet');
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

test('with every default accepted the questions come in the order: accounts, orchestrator, author, reviewer, lead reviewer, repos, recap', async () => {
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
  const alone = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'one.json') }, alone.ui, one.deps);
  expect(alone.asked.some((m) => m.startsWith('Turn failover on'))).toBe(false);
  expect(alone.notes.filter((n) => n.title?.startsWith('Failover for the')).map((n) => n.message)).toEqual(['Failover needs a second account, so the author has none.', 'Failover needs a second account, so the reviewer has none.']);

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
