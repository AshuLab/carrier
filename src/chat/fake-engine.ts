import { mkdirSync } from 'node:fs';
import { createServer } from 'node:net';
import { enginePlacesOf } from '../config/places.ts';

/** What a fake engine answers to `reload`: it applies the files, or keeps its settings and says why. */
export type FakeEngineAnswer = 'applied' | { error: string; code: string; params: Record<string, string | number> };

/** An engine socket in `folder` that answers its hello and each `reload` (test double of the control server); the returned `reloads` counts them and `close` ends it. */
export async function fakeEngine(folder: string, answer: FakeEngineAnswer) {
  const socketPath = enginePlacesOf(folder).socket;
  mkdirSync(enginePlacesOf(folder).state, { recursive: true });
  let reloads = 0;
  const server = createServer((socket) => {
    socket.setEncoding('utf8');
    socket.write(`${JSON.stringify({ event: 'hello', protocol: 1, pid: process.pid, startedAt: 0, version: 'test', capabilities: ['reload'] })}\n`);
    socket.on('data', (chunk: string) => {
      for (const line of chunk.split('\n').filter((text) => text !== '')) {
        const { id } = JSON.parse(line);
        reloads++;
        socket.write(`${JSON.stringify(answer === 'applied' ? { id, ok: true } : { id, ok: false, ...answer })}\n`);
      }
    });
  });
  await new Promise<void>((resolve) => server.listen(socketPath, resolve));
  return { get reloads() { return reloads; }, close: () => void server.close() };
}
