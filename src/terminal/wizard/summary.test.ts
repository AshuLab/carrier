import { expect, test } from 'vitest';
import type { Role } from './build-config.ts';
import { summary } from './summary.ts';

const role = (provider: string): Role => ({ identity: { kind: 'gh' }, provider, model: 'm' });
const providers = { claude: { harness: 'claude' as const }, codex: { harness: 'codex' as const } };
const recap = (extras: Parameters<typeof summary>[9], failover?: Parameters<typeof summary>[4]) => summary(['A/b'], role('claude'), role('codex'), providers, failover, '/c.json', '/p.json', undefined, undefined, extras);
const line = (text: string, label: string) => text.split('\n').find((l) => l.startsWith(label));

test('the recap shows what each extra reviewer fails over to, or that it uses the Reviewer\'s, in that reviewer\'s own line', () => {
  const text = recap([{ role: role('claude'), failover: [{ provider: 'codex', model: 'gpt-x' }, { provider: 'claude' }] }, { role: role('codex') }], { triggers: [], roles: { reviewer: [{ provider: 'claude', model: 'opus' }] } } as never);
  const [two, three] = [text.indexOf('Reviewer 2'), text.indexOf('Reviewer 3')];
  expect(text.slice(two, three)).toContain('failover: codex gpt-x → claude');
  expect(text.slice(three, text.indexOf('Failover'))).toContain("failover: the Reviewer's");
  expect(line(text, 'Failover')).toContain('reviewer: claude opus'); // the roles with a config key keep their summary line
});

test('an extra reviewer with no failover says nothing about it when the Reviewer has none either', () => {
  expect(recap([{ role: role('claude') }])).not.toContain('failover:');
});
