// Prints only the SHAPE of the user's settings that matter for permissions (counts, never values), to read the results against.
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
const dir = process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), '.claude');
console.log('CLAUDE_CONFIG_DIR set:', process.env.CLAUDE_CONFIG_DIR !== undefined);
for (const f of ['settings.json', 'settings.local.json']) {
  const p = join(dir, f);
  if (!existsSync(p)) { console.log(f, 'absent'); continue; }
  const s = JSON.parse(readFileSync(p, 'utf8'));
  const perm = s.permissions ?? {};
  console.log(f, { keys: Object.keys(s).filter((k) => k !== 'env'), defaultMode: perm.defaultMode, allow: perm.allow?.length ?? 0, deny: perm.deny?.length ?? 0, ask: perm.ask?.length ?? 0, hookEvents: Object.keys(s.hooks ?? {}), hasEnvKeys: Object.keys(s.env ?? {}).length });
}
