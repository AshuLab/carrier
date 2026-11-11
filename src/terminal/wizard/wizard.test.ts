import { join } from 'node:path';
import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../config/load.ts';
import { Cancelled, type Ui } from '../prompts/types.ts';
import { asFiles, fakeDeps, fakeMachine, okCheck, providersWritten, quietUi, useTempDir } from './testing.ts';
import { runInit } from './wizard.ts';

const dir = useTempDir();

const withHome = async <T>(run: () => Promise<T>) => {
  process.env.CARRIER_HOME = join(dir, 'home');
  try {
    return await run();
  } finally {
    delete process.env.CARRIER_HOME;
  }
};

const existingKey = `A config already exists at ${join(dir, 'home', 'config.json')}`;

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
  const { ui, asked } = quietUi({ 'Repos to watch (owner/name, comma separated)': 'AshuLab/a, AshuLab/b' });
  const out = join(dir, 'a.json');
  const result = await runInit({ out }, ui, deps);

  expect(JSON.parse(written[out]!)).toEqual({
    repos: [{ name: 'AshuLab/a' }, { name: 'AshuLab/b' }],
    profiles: { 'artanis-agent': { kind: 'forge', agent: 'artanis-agent' }, 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' } },
    orchestratorProfile: 'artanis-agent',
    agents: {
      author: { profile: 'artanis-agent', provider: 'claude', model: 'sonnet' },
      reviewer: { profile: 'tassadar-agent', provider: 'codex', model: 'gpt-test' }, // author's bot is not offered again; codex default from ~/.codex
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
  expect(config.agents).toEqual({ author: { profile: 'artanis-agent', provider: 'codex', model: 'm1' }, reviewer: { profile: 'gh', provider: 'claude', model: 'm2' } });
  expect(loadConfig(defaults, config, providersWritten(written) as never).ok).toBe(true);
});

test('providers are not asked: what the detector found is shown and written switched off, with the extras asked for, and the recap says where the file goes', async () => {
  const { deps, written } = fakeDeps({ machine: fakeMachine({ version: async (command) => (command.endsWith('claude') ? '2.1.3' : '0.5.0'), login: async (harness) => (harness === 'codex' ? 'out' : 'in'), localModels: async (kind) => (kind === 'ollama' ? ['qwen3:8b'] : Promise.reject(new Error('down'))) }) });
  const { ui, asked, notes } = quietUi({ 'Add another AI provider?': [true, false], 'Which agent CLI runs this provider?': 'claude', 'Where does this provider run?': 'ollama' });
  const out = join(dir, 'd.json');
  const folder = join(dir, 'carrier-home');
  await runInit({ repo: ['A/b'], out }, ui, deps, folder);
  expect(asked.indexOf('Which agent CLI runs this provider?')).toBeGreaterThan(asked.indexOf('Add another AI provider?')); // only the extras are asked, after the gate
  expect(notes.find((n) => n.title === 'Found on this Mac')!.message).toBe(
    ['Claude Code  /opt/bin/claude · 2.1.3 · signed in', 'Codex        /opt/bin/codex · 0.5.0 · signed out', 'Antigravity  not found', 'LM Studio    not running', 'Ollama       running · 1 models'].join('\n'),
  );
  expect(providersWritten(written, folder)).toEqual({ claude: { harness: 'claude' }, codex: { harness: 'codex' }, 'claude-2': { harness: 'claude', provider: 'ollama' } });
  expect(notes.find((n) => n.title === 'This is what will be saved')!.message).toContain(`Accounts in ${join(folder, 'providers.json')}`); // not next to --out
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

test('each role gets its own box, and the author is fully asked before the reviewer', async () => {
  const notes: string[] = [];
  const order: string[] = [];
  const { ui } = quietUi();
  const spy: Ui = {
    ...ui,
    note: (_m, title) => notes.push(title),
    select: async (o) => (order.push(o.message), ui.select(o)),
    text: async (o) => (order.push(o.message), ui.text(o)),
  };
  await runInit({ repo: ['A/b'], out: join(dir, 'o.json') }, spy, fakeDeps().deps);
  expect(notes.filter((t) => t === 'Author' || t === 'Reviewer')).toEqual(['Author', 'Reviewer']);
  expect(order.filter((m) => /author|reviewer/i.test(m))).toEqual([
    'GitHub identity for the author',
    'GitHub identity for the reviewer',
    'Which AI provider runs the author?',
    'Model for the author',
    'Effort for the author',
    'Author persona',
    'Which AI provider runs the reviewer?',
    'Model for the reviewer',
    'Effort for the reviewer',
    'Reviewer persona',
  ]);
});

test('the recap lists what will be saved, and declining it writes nothing', async () => {
  const { deps, written } = fakeDeps();
  const notes: Record<string, string> = {};
  const { ui } = quietUi({ 'Save it?': false });
  const spy: Ui = { ...ui, note: (m, title) => void (notes[title] = m) };
  await expect(runInit({ repo: ['A/b'], out: join(dir, 'u.json') }, spy, deps)).rejects.toBeInstanceOf(Cancelled);
  expect(written).toEqual({});
  expect(notes['This is what will be saved']).toMatch(/Repos {7}A\/b\nProviders {3}claude, codex\nAuthor {6}artanis-agent · claude \(Claude Code\) · sonnet\nReviewer {4}tassadar-agent · codex \(Codex\) · gpt-test\nSaved to {4}/);
});

test('--yes skips the recap and the start question', async () => {
  const { deps } = fakeDeps();
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'v.json'), yes: true }, ui, deps);
  expect(asked).not.toContain('Save it?');
  expect(asked.some((q) => q.startsWith('Start Carrier'))).toBe(false);
});

test('an existing config can be edited: its answers are the starting points and no question about the file is asked', async () => {
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(existing) });
  const { ui, asked } = quietUi();
  await withHome(() => runInit({}, ui, deps));
  const [path] = Object.keys(written);
  expect(path).toBe(join(dir, 'home', 'config.json'));
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
  expect(JSON.parse(written[join(dir, 'home', 'config.json')]!).repos).toEqual([{ name: 'AshuLab/carrier' }]); // the origin suggestion, not the old repos
});

test('"Leave it as it is" cancels, and an unreadable config is said so instead of crashing', async () => {
  const left = fakeDeps({ exists: () => true });
  await expect(withHome(() => runInit({}, quietUi({ [existingKey]: 'cancel' }).ui, left.deps))).rejects.toBeInstanceOf(Cancelled);
  expect(left.written).toEqual({});
  const broken = fakeDeps({ exists: () => true, readConfig: () => ({ nope: 1 }) });
  const { ui, asked } = quietUi();
  await withHome(() => runInit({}, ui, broken.deps));
  expect(asked.some((q) => q.startsWith('warn:') && q.includes('is not a valid config'))).toBe(true);
});

test('after good checks it shows what is waiting and offers to start; with failed checks it does neither', async () => {
  const notes: Record<string, string> = {};
  const good = fakeDeps({ readyEpics: async () => ({ 'AshuLab/carrier': 2, 'AshuLab/x': undefined }) });
  const { ui, asked: started } = quietUi({ 'Start Carrier now? (Ctrl+C stops it)': true });
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
test('the effort of each role is asked after its model, written when chosen, and the config loads', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi({ 'Effort for the reviewer': 'xhigh' });
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
  const { ui } = quietUi();
  const initial: Record<string, unknown> = {};
  const notes: Record<string, string> = {};
  await withHome(() => runInit({}, { ...ui, select: async (o) => ((initial[o.message] = o.initialValue), ui.select(o)), note: (m, t) => void (notes[t] = m) }, deps));
  expect(initial['Effort for the author']).toBe('high');
  expect(initial['GitHub identity for the author']).toBe('gh');
  expect(notes['This is what will be saved']).toContain('Identity    shared: author and reviewer are the same account, and the signature in what they publish will show it');
  const { providers, ...config } = shared;
  expect(JSON.parse(written[join(dir, 'home', 'config.json')]!)).toEqual(config);
  expect(providersWritten(written, join(dir, 'home'))).toEqual(providers);
});

// Personas: a name and a prompt per role, asked right after its agent.
const titled = (role: string) => role.split(' ').map((w) => `${w[0]!.toUpperCase()}${w.slice(1)}`).join(' ');
const nameOf = (role: string) => `${titled(role)} persona: give it a name`;
const promptOf = (role: string) => `${titled(role)} persona: describe how it behaves`;
const gateOf = (role: string) => `${titled(role)} persona`;

test('each role is asked for a persona after its agent, the author first; Default skips name and prompt and leaves none', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({ [gateOf('reviewer')]: 'set', [nameOf('reviewer')]: ' Rex ', [promptOf('reviewer')]: 'Be strict about migrations.' });
  const out = join(dir, 'p1.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  const order = [gateOf('author'), nameOf('author'), promptOf('author'), 'Which AI provider runs the reviewer?', gateOf('reviewer'), nameOf('reviewer'), promptOf('reviewer')];
  expect(asked.filter((q) => order.includes(q))).toEqual([gateOf('author'), 'Which AI provider runs the reviewer?', gateOf('reviewer'), nameOf('reviewer'), promptOf('reviewer')]);
  expect(asked.indexOf('Which AI provider runs the author?')).toBeLessThan(asked.indexOf(gateOf('author')));
  expect(asked.indexOf(gateOf('author'))).toBeLessThan(asked.indexOf('Which AI provider runs the reviewer?'));
  const agents = JSON.parse(written[out]!).agents;
  expect(agents.author).not.toHaveProperty('persona');
  expect(agents.reviewer.persona).toEqual({ name: 'Rex', prompt: 'Be strict about migrations.' });
});

test('personas are asked under a shared identity too, and the config loads', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi({ 'GitHub identity for the author': 'gh', 'GitHub identity for the reviewer': 'gh', [gateOf('author')]: 'set', [nameOf('author')]: 'Ada' });
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
  const { ui } = quietUi({ [gateOf('author')]: 'set' });
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
  const { ui } = quietUi({ [gateOf('reviewer')]: 'set' });
  const defaultsSeen: Record<string, string | undefined> = {};
  const notes: Record<string, string> = {};
  await withHome(() => runInit({}, { ...ui, text: async (o) => (defaultsSeen[o.message] = o.defaultValue, ui.text(o)), note: (m, t) => void (notes[t] = m) }, deps));
  expect(defaultsSeen[nameOf('reviewer')]).toBe('Rex');
  expect(defaultsSeen[promptOf('reviewer')]).toBe('Be strict.');
  expect(notes['This is what will be saved']).toContain('persona: Rex · Be strict.');
  const { providers: _, ...config } = withPersona;
  expect(JSON.parse(written[join(dir, 'home', 'config.json')]!)).toEqual(config);
});

test('editing a persona: a dash clears the field, and clearing both leaves no persona', async () => {
  const withPersona = { ...existing, agents: { ...existing.agents, reviewer: { ...existing.agents.reviewer, persona: { name: 'Rex', prompt: 'Be strict.' } } } };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(withPersona) });
  const { ui } = quietUi({ [gateOf('reviewer')]: 'set', [nameOf('reviewer')]: '-', [promptOf('reviewer')]: '-' });
  await withHome(() => runInit({}, ui, deps));
  expect(JSON.parse(written[join(dir, 'home', 'config.json')]!).agents.reviewer).not.toHaveProperty('persona');
});

test('editing a persona: Keep leaves it as it was without asking its fields, Remove drops it', async () => {
  const withPersona = { ...existing, agents: { ...existing.agents, reviewer: { ...existing.agents.reviewer, persona: { name: 'Rex', prompt: 'Be strict.' } } } };
  for (const [answer, expected] of [[undefined, { name: 'Rex', prompt: 'Be strict.' }], ['default', undefined]] as const) {
    const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(withPersona) });
    const { ui, asked } = quietUi(answer ? { [gateOf('reviewer')]: answer } : {});
    await withHome(() => runInit({}, ui, deps));
    expect(asked).not.toContain(nameOf('reviewer'));
    expect(JSON.parse(written[join(dir, 'home', 'config.json')]!).agents.reviewer.persona).toEqual(expected);
  }
});

test('adding a lead reviewer asks its identity, provider, model and persona, and writes it to agents', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({
    'Add a Lead Reviewer to the workflow?': true,
    'GitHub identity for the lead reviewer': 'forge:tassadar-agent',
    'Which AI provider runs the lead reviewer?': 'claude',
    'Model for the lead reviewer': 'opus',
    [gateOf('lead reviewer')]: 'set',
    [nameOf('lead reviewer')]: 'Architect',
  });
  const out = join(dir, 'lead.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked).toContain('Add a Lead Reviewer to the workflow?');
  expect(asked).toContain('GitHub identity for the lead reviewer');
  expect(asked).toContain('Which AI provider runs the lead reviewer?');
  expect(asked).toContain('Model for the lead reviewer');

  const config = JSON.parse(written[out]!);
  expect(config.agents.leadReviewer).toEqual({
    profile: 'tassadar-agent',
    provider: 'claude',
    model: 'opus',
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
  });
  expect(loadConfig(defaults, config, providersWritten(written) as never).ok).toBe(true);
});
