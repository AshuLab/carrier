import { join } from 'node:path';
import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../config/load.ts';
import { Cancelled, type Ui } from '../prompts/types.ts';
import { fakeDeps, okCheck, quietUi, useTempDir } from './testing.ts';
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
  agentOptions: { claude: { harness: 'claude', model: 'opus' }, codex: { harness: 'codex', model: 'gpt-test' } },
  agents: { author: { profile: 'tassadar-agent', option: 'claude' }, reviewer: { profile: 'gh', option: 'codex' } },
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
    agentOptions: { claude: { harness: 'claude', model: 'sonnet' }, codex: { harness: 'codex', model: 'gpt-test' } },
    agents: {
      author: { profile: 'artanis-agent', option: 'claude' },
      reviewer: { profile: 'tassadar-agent', option: 'codex' }, // author's bot is not offered again; codex default from ~/.codex
    },
  });
  expect(doctored).toMatchObject({ pollIntervalMinutes: 5 }); // the doctor gets the merged config
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
  expect(config.agentOptions).toEqual({ codex: { harness: 'codex', model: 'm1' }, claude: { harness: 'claude', model: 'm2' } });
  expect(config.agents).toEqual({ author: { profile: 'artanis-agent', option: 'codex' }, reviewer: { profile: 'gh', option: 'claude' } });
  expect(loadConfig(defaults, config).ok).toBe(true);
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
    'GitHub identity for the author', 'Which agent CLI runs the author?', 'Model for the author',
    'Author persona: give it a name', 'Author persona: describe how it behaves',
    'GitHub identity for the reviewer', 'Which agent CLI runs the reviewer?', 'Model for the reviewer',
    'Reviewer persona: give it a name', 'Reviewer persona: describe how it behaves',
  ]);
});

test('the recap lists what will be saved, and declining it writes nothing', async () => {
  const { deps, written } = fakeDeps();
  const notes: Record<string, string> = {};
  const { ui } = quietUi({ 'Save it?': false });
  const spy: Ui = { ...ui, note: (m, title) => void (notes[title] = m) };
  await expect(runInit({ repo: ['A/b'], out: join(dir, 'u.json') }, spy, deps)).rejects.toBeInstanceOf(Cancelled);
  expect(written).toEqual({});
  expect(notes['This is what will be saved']).toMatch(/Repos {5}A\/b\nAuthor {4}artanis-agent · Claude Code · sonnet\nReviewer {2}tassadar-agent · Codex · gpt-test\nSaved to {2}/);
});

test('--yes skips the recap and the start question', async () => {
  const { deps } = fakeDeps();
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'v.json'), yes: true }, ui, deps);
  expect(asked).not.toContain('Save it?');
  expect(asked.some((q) => q.startsWith('Start Carrier'))).toBe(false);
});

test('an existing config can be edited: its answers are the starting points and no question about the file is asked', async () => {
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: () => existing });
  const { ui, asked } = quietUi();
  await withHome(() => runInit({}, ui, deps));
  const [path] = Object.keys(written);
  expect(path).toBe(join(dir, 'home', 'config.json'));
  expect(JSON.parse(written[path!]!)).toEqual({
    repos: [{ name: 'X/y' }, { name: 'X/z' }],
    profiles: { 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' }, gh: { kind: 'gh' } },
    orchestratorProfile: 'tassadar-agent',
    agentOptions: { claude: { harness: 'claude', model: 'opus' }, codex: { harness: 'codex', model: 'gpt-test' } },
    agents: { author: { profile: 'tassadar-agent', option: 'claude' }, reviewer: { profile: 'gh', option: 'codex' } },
  });
  expect(asked).not.toContain('Where should the config be saved?');
  expect(asked.some((q) => q.endsWith('exists. Overwrite it?'))).toBe(false);
});

test('"Start over" ignores the old answers but still replaces that file without asking again', async () => {
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: () => existing });
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
  await expect(runInit({ repo: ['A/b'] }, ui, fakeDeps({ which: (c) => c === 'git' || c === 'gh' }).deps)).rejects.toThrow(/an agent CLI, any of these:\n {4}claude: install Claude Code .*\n {4}codex: .*\n {4}agy: /);
  expect(asked).toEqual([]); // nothing was asked
});

test('gh without a login is a warning, not a stop', async () => {
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'm2.json') }, ui, fakeDeps({ ghLogin: () => undefined }).deps);
  expect(asked.find((q) => q.startsWith('warn:gh is not logged in'))).toContain('gh auth login');
});

// A shared identity: the gh login for both roles, no Agent Forge.
const sharedMessage = 'GitHub identities: one for each role, or one shared?';
const touchesForge = () => {
  throw new Error('Agent Forge must not be read under a shared identity');
};

test('choosing shared by answer asks no identity, never touches Forge, and writes a config that loads', async () => {
  const { deps, written } = fakeDeps({ forgeAgents: touchesForge, forgeAdd: touchesForge });
  const { ui, asked } = quietUi({ [sharedMessage]: 'shared', 'Use your gh login for both roles?': true });
  const notes: string[] = [];
  const out = join(dir, 's1.json');
  await runInit({ repo: ['A/b'], out }, { ...ui, note: (_m, title) => void notes.push(title) }, deps);
  const written1 = JSON.parse(written[out]!);
  expect(written1).toEqual({
    repos: [{ name: 'A/b' }],
    identities: 'shared',
    profiles: { gh: { kind: 'gh' } },
    orchestratorProfile: 'gh',
    agentOptions: { claude: { harness: 'claude', model: 'sonnet' }, codex: { harness: 'codex', model: 'gpt-test' } },
    agents: { author: { profile: 'gh', option: 'claude' }, reviewer: { profile: 'gh', option: 'codex' } },
  });
  expect(loadConfig(defaults, written1).ok).toBe(true);
  expect(asked.some((q) => q.startsWith('GitHub identity for'))).toBe(false);
  expect(notes.indexOf('Shared identity')).toBeGreaterThan(-1);
});

test('--identities shared with --yes is the consent, and the note about the token is still printed', async () => {
  const { deps, written } = fakeDeps({ forgeAgents: touchesForge });
  const { ui, asked } = quietUi();
  const notes: Record<string, string> = {};
  const out = join(dir, 's2.json');
  await runInit({ repo: ['A/b'], identities: 'shared', out, yes: true }, { ...ui, note: (m, t) => void (notes[t] = m) }, deps);
  expect(notes['Shared identity']).toContain('everything your gh token can do');
  expect(asked.some((q) => q.startsWith('Use your gh login'))).toBe(false);
  expect(JSON.parse(written[out]!).identities).toBe('shared');
});

test('declining the note goes back to the question, where separate can be picked', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi({ 'Use your gh login for both roles?': false });
  let n = 0;
  const out = join(dir, 's3.json');
  await runInit({ repo: ['A/b'], out }, { ...ui, select: async (o) => (o.message === sharedMessage ? (((n += 1) === 1 ? 'shared' : 'separate') as never) : ui.select(o)) }, deps);
  expect(JSON.parse(written[out]!)).not.toHaveProperty('identities');
});

test('a shared identity without a gh login stops with gh auth login and writes nothing', async () => {
  const { deps, written } = fakeDeps({ ghLogin: () => undefined });
  await expect(runInit({ repo: ['A/b'], identities: 'shared', out: join(dir, 's4.json'), yes: true }, quietUi().ui, deps)).rejects.toThrow('gh auth login');
  expect(written).toEqual({});
});

test('--identities shared with a profile flag fails and says the shared identity is the gh login', async () => {
  for (const profile of [{ authorProfile: 'gh' }, { reviewerProfile: 'forge:bot' }]) {
    const { deps, written } = fakeDeps();
    await expect(runInit({ repo: ['A/b'], identities: 'shared', ...profile, out: join(dir, 's5.json'), yes: true }, quietUi().ui, deps)).rejects.toThrow('the shared identity is the gh login');
    expect(written).toEqual({});
  }
  await expect(runInit({ repo: ['A/b'], identities: 'both', out: join(dir, 's5.json'), yes: true }, quietUi().ui, fakeDeps().deps)).rejects.toThrow('expected separate or shared');
});

test('--identities separate asks the identity questions and writes no identities key', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 's6.json');
  await runInit({ repo: ['A/b'], identities: 'separate', out }, ui, deps);
  expect(asked).not.toContain(sharedMessage);
  expect(asked).toContain('GitHub identity for the author');
  expect(JSON.parse(written[out]!)).not.toHaveProperty('identities');
});

test('editing a shared config starts with shared selected, and the recap shows the identity setup', async () => {
  const shared = {
    repos: [{ name: 'X/y' }],
    identities: 'shared',
    profiles: { gh: { kind: 'gh' } },
    orchestratorProfile: 'gh',
    agentOptions: { claude: { harness: 'claude', model: 'opus' }, codex: { harness: 'codex', model: 'gpt-test' } },
    agents: { author: { profile: 'gh', option: 'claude' }, reviewer: { profile: 'gh', option: 'codex' } },
  };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: () => shared, forgeAgents: touchesForge });
  const { ui } = quietUi({ 'Use your gh login for both roles?': true });
  const initial: unknown[] = [];
  const notes: Record<string, string> = {};
  await withHome(() => runInit({}, { ...ui, select: async (o) => (o.message === sharedMessage && initial.push(o.initialValue), ui.select(o)), note: (m, t) => void (notes[t] = m) }, deps));
  expect(initial).toEqual(['shared']);
  expect(notes['This is what will be saved']).toContain('Identity  shared: both roles act as your gh login');
  expect(JSON.parse(written[join(dir, 'home', 'config.json')]!)).toEqual(shared);
});

// Personas: a name and a prompt per role, asked right after its agent.
const titled = (role: string) => `${role[0]!.toUpperCase()}${role.slice(1)}`;
const nameOf = (role: string) => `${titled(role)} persona: give it a name`;
const promptOf = (role: string) => `${titled(role)} persona: describe how it behaves`;

test('each role is asked name and prompt after its agent, the author first, and a role with both skipped has no persona', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({ [nameOf('reviewer')]: ' Rex ', [promptOf('reviewer')]: 'Be strict about migrations.' });
  const out = join(dir, 'p1.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  const order = [nameOf('author'), promptOf('author'), 'Model for the reviewer', nameOf('reviewer'), promptOf('reviewer')];
  expect(asked.filter((q) => order.includes(q))).toEqual([nameOf('author'), promptOf('author'), 'Model for the reviewer', nameOf('reviewer'), promptOf('reviewer')]);
  expect(asked.indexOf('Model for the author')).toBeLessThan(asked.indexOf(nameOf('author')));
  expect(asked.indexOf(promptOf('author'))).toBeLessThan(asked.indexOf('GitHub identity for the reviewer'));
  const agents = JSON.parse(written[out]!).agents;
  expect(agents.author).not.toHaveProperty('persona');
  expect(agents.reviewer.persona).toEqual({ name: 'Rex', prompt: 'Be strict about migrations.' });
});

test('personas are asked under a shared identity too, and the config loads', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi({ [sharedMessage]: 'shared', 'Use your gh login for both roles?': true, [nameOf('author')]: 'Ada' });
  const out = join(dir, 'p2.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  const user = JSON.parse(written[out]!);
  expect(user.agents.author.persona).toEqual({ name: 'Ada' });
  expect(loadConfig(defaults, user).ok).toBe(true);
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
  const { ui } = quietUi();
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
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: () => withPersona });
  const { ui } = quietUi();
  const defaultsSeen: Record<string, string | undefined> = {};
  const notes: Record<string, string> = {};
  await withHome(() => runInit({}, { ...ui, text: async (o) => (defaultsSeen[o.message] = o.defaultValue, ui.text(o)), note: (m, t) => void (notes[t] = m) }, deps));
  expect(defaultsSeen[nameOf('reviewer')]).toBe('Rex');
  expect(defaultsSeen[promptOf('reviewer')]).toBe('Be strict.');
  expect(defaultsSeen[nameOf('author')]).toBe('');
  expect(notes['This is what will be saved']).toContain('persona: Rex · Be strict.');
  expect(JSON.parse(written[join(dir, 'home', 'config.json')]!)).toEqual(withPersona);
});

test('editing a persona: a dash clears the field, and clearing both leaves no persona', async () => {
  const withPersona = { ...existing, agents: { ...existing.agents, reviewer: { ...existing.agents.reviewer, persona: { name: 'Rex', prompt: 'Be strict.' } } } };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: () => withPersona });
  const { ui } = quietUi({ [nameOf('reviewer')]: '-', [promptOf('reviewer')]: '-' });
  await withHome(() => runInit({}, ui, deps));
  expect(JSON.parse(written[join(dir, 'home', 'config.json')]!).agents.reviewer).not.toHaveProperty('persona');
});
