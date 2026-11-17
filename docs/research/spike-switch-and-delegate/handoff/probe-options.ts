// no turns: opens each harness once and prints the models it lists, then closes.
import { mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { claudeChatRunner } from '../../../../src/chat/claude.ts';
import { codexChatRunner } from '../../../../src/chat/codex.ts';

const folder = realpathSync(mkdtempSync(join(tmpdir(), 'hf-probe-')));
try {
  for (const [name, runner] of [['claude', claudeChatRunner()], ['codex', codexChatRunner()]] as const) {
    const conv = await runner.open({ folder, env: process.env, options: {} });
    try {
      for (const o of conv.options) console.log(name, o.id, 'current=', o.current, o.values.map((v) => v.id + (v.detail ? `(${v.detail.slice(0, 50)})` : '')).join(' | '));
      console.log(name, 'commands', conv.commands.length);
    } finally {
      await conv.close();
    }
  }
} finally {
  rmSync(folder, { recursive: true, force: true });
}
