import { expect, test, vi } from 'vitest';

const spawn = vi.hoisted(() => vi.fn(() => ({ on: () => ({ unref: () => {} }) })));
vi.mock('node:child_process', () => ({ spawn }));
const { openUrl } = await import('./open-url.ts');

test('only GitHub issue and PR pages reach `open`', () => {
  openUrl('https://github.com/AshuLab/carrier/pull/44');
  openUrl('https://github.com/AshuLab/carrier/issues/3');
  expect(spawn).toHaveBeenCalledTimes(2);
  for (const bad of ['https://evil.example/x', 'file:///etc/passwd', 'https://github.com/a/b/pull/1; rm -rf ~', 'https://github.com/a/b/tree/main', '-a Calculator']) openUrl(bad);
  expect(spawn).toHaveBeenCalledTimes(2);
});
