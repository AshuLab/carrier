// B2: does thread/start `config` merge with the person's own configuration or replace it? Names only, never contents.
import { rmSync } from 'node:fs';
import { join } from 'node:path';
import { App, tmp } from './lib.ts';
import { startToy } from './toy.ts';

const folder = tmp('cdxb-');
const toy = await startToy(join(folder, 'ping.log'), folder);
const inject = { 'mcp_servers.carrier-chat': { url: toy.url, default_tools_approval_mode: 'approve', http_headers: { Authorization: `Bearer ${toy.token}` } } };

async function names(app: App, threadId: string | undefined) {
  const r = await app.request('mcpServerStatus/list', { detail: 'toolsAndAuthOnly', ...(threadId && { threadId }) });
  return (r.data as any[]).map((s) => `${s.name}[${s.runtimeStatus ?? '-'}${s.toolsError ? ',toolsError' : ''},tools=${Object.keys(s.tools ?? {}).length}]`).sort();
}
const configNames = async (app: App) => {
  const r = await app.request('config/read', { includeLayers: false, cwd: folder });
  return Object.keys(r.config.mcp_servers ?? {}).sort();
};

async function run(label: string, args: string[], thread: 'none' | 'inject' | 'plain') {
  const app = new App(`b2-${label.split(' ')[0]}`, folder, args);
  app.secrets.push(toy.token);
  try {
    await app.init();
    const cfg = await configNames(app);
    const noThread = await names(app, undefined);
    let withThread: string[] | undefined;
    if (thread !== 'none') {
      const r = await app.request('thread/start', { cwd: folder, approvalPolicy: 'never', sandbox: 'read-only', model: 'mock-model', ...(thread === 'inject' && { config: inject }) });
      await new Promise((x) => setTimeout(x, 3000)); // let the servers start
      withThread = await names(app, r.thread.id);
    }
    console.log(`\n== ${label}\n config/read mcp_servers keys: ${cfg.join(', ') || '(none)'}\n mcpServerStatus/list (no thread): ${noThread.join(', ') || '(none)'}\n mcpServerStatus/list (thread):    ${withThread?.join(', ') ?? 'n/a'}`);
  } finally { await app.close(); }
}
try {
  await run('A0 person config only, thread without config', [], 'plain');
  await run('A1 injected only (thread/start config)', [], 'inject');
  await run('A2 injected + second server by -c', ['-c', 'mcp_servers.second-by-cli={command="/usr/bin/true"}'], 'inject');
  await run('A3 -c second server only, no injection', ['-c', 'mcp_servers.second-by-cli={command="/usr/bin/true"}'], 'plain');
  await run('A4 injected, with -c mcp_servers={} (try to blank the person list)', ['-c', 'mcp_servers={}'], 'inject');
} finally { await toy.close(); rmSync(folder, { recursive: true, force: true }); }
