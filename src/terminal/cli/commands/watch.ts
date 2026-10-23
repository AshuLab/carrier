import type { Config } from '../../../config/schema.ts';
import type { PanelSnapshot } from '../../../status/types.ts';
import { renderDashboard } from '../../dashboard/dashboard.ts';
import { startInteractivePanel, type Controls } from '../../dashboard/interactive.ts';
import { startPanel } from '../../dashboard/panel.ts';
import { ControlUnreachable, type CarrierClient } from '../control-client.ts';
import { openUrl } from '../open-url.ts';
import { attach } from './status.ts';

const REFRESH_MS = 1000;
const TAIL_LINES = 18; // what the logs screen shows; the cards' "now" lines take the end of the same answer

/**
 * The panel's `Controls` and snapshot over a control socket. The panel reads both synchronously, so the snapshot and
 * each execution's output are kept from the last answer and renewed in the background: `refresh` for the snapshot,
 * a new `tail` request at each read of the output. `lost` is called when the socket stops answering.
 */
export function socketPanel(client: Pick<CarrierClient, 'request'>, { open, quit, lost }: { open: (url: string) => void; quit: () => void; lost: () => void }) {
  let latest: PanelSnapshot;
  const tails = new Map<string, { lines: string[]; asking: boolean }>();
  // Another failure (the engine refused one request) leaves the panel as it was.
  const guard = (request: Promise<unknown>) => request.catch((error) => error instanceof ControlUnreachable && lost());

  const controls: Controls = {
    poll: () => guard(client.request('checkNow')),
    setPaused: (paused) => guard(client.request(paused ? 'pause' : 'resume')),
    open,
    quit,
    logs: (executionId, count) => {
      const tail = tails.get(executionId) ?? { lines: [], asking: false };
      tails.set(executionId, tail);
      if (tail.asking === false) {
        tail.asking = true;
        void guard(client.request('tail', { executionId, lines: TAIL_LINES }).then((lines) => (tail.lines = lines as string[]))).finally(() => (tail.asking = false));
      }
      return tail.lines.slice(-count);
    },
  };
  return {
    controls,
    snapshot: () => latest,
    /** Asks for the snapshot; rejects when the socket does not answer. */
    refresh: async () => {
      latest = (await client.request('snapshot')) as PanelSnapshot;
    },
  };
}

/** Shows the live panel of the running Carrier, with the foreground panel's keys; `q` and Ctrl+C leave and Carrier keeps running. Exit 0 left; 1 not running, or it stopped; 2 another protocol. */
export async function watchCommand(config: Config): Promise<number> {
  const client = await attach(config);
  if (typeof client === 'number') return client;

  return new Promise<number>((resolve) => {
    let stop = () => {};
    let timer: NodeJS.Timeout | undefined;
    let finished = false;
    const finish = (code: number, message?: string) => {
      if (finished) return;
      finished = true;
      clearInterval(timer);
      process.off('SIGINT', leave);
      stop(); // the cursor and the keys back before anything else is printed
      client.close();
      if (message) process.stderr.write(`${message}\n`);
      resolve(code);
    };
    const leave = () => finish(0);
    const panel = socketPanel(client, { open: openUrl, quit: leave, lost: () => finish(1, 'Carrier stopped.') });
    process.once('SIGINT', leave); // a Ctrl+C that is not a key: no raw mode, because stdin is not a terminal

    panel.refresh().then(
      () => {
        const { stdout, stdin } = process;
        stop =
          stdout.isTTY && stdin.isTTY
            ? startInteractivePanel({ snapshot: panel.snapshot, out: stdout, stdin, controls: panel.controls, quit: 'leave' })
            : startPanel(panel.snapshot, stdout, REFRESH_MS, (s, columns) => renderDashboard(s, { columns, quit: 'leave' }));
        let asking = false;
        timer = setInterval(() => {
          if (asking) return;
          asking = true;
          panel.refresh().catch(() => finish(1, 'Carrier stopped.')).finally(() => (asking = false));
        }, REFRESH_MS);
      },
      () => finish(1, 'Carrier is running but does not answer. Try again, or check its log.'),
    );
  });
}
