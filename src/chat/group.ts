import { accessSync, constants } from 'node:fs';
import { resolveBinary } from '../harnesses/common.ts';

/** The binary to run for a chat agent: `command` when it is a path, else `command` or `fallback` looked up on the path. Throws when there is none. */
export const resolveAgentBinary = (fallback: string, command: string | undefined, env: NodeJS.ProcessEnv) => {
  if (command?.includes('/')) return accessSync(command, constants.X_OK), command;
  return resolveBinary(command ?? fallback, env.PATH);
};

/** SIGTERM to the agent's whole group (the agent process and the servers it started), SIGKILL if it is still there after a few seconds. */
export async function endGroup(pid: number) {
  const send = (signal: NodeJS.Signals) => {
    try {
      process.kill(-pid, signal);
      return true;
    } catch {
      return false; // the group is gone
    }
  };
  if (!send('SIGTERM')) return;
  for (let i = 0; i < 30; i++) {
    await new Promise((resolve) => setTimeout(resolve, 100));
    if (!send(0 as never)) return;
  }
  send('SIGKILL');
}
