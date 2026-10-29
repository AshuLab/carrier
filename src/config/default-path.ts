import { homedir } from 'node:os';
import { join } from 'node:path';

export const expandHome = (path: string) => (path === '~' || path.startsWith('~/') ? join(homedir(), path.slice(1)) : path);

/** Carrier's home: `CARRIER_HOME`, else `~/.carrier`. Holds the engine's config and one subfolder per process (`chat/`). */
export const carrierHome = () => process.env.CARRIER_HOME || join(homedir(), '.carrier');

/** Where `carrier init` writes the config and where `carrier` looks when there is no `--config`: global, one per user. */
export const defaultConfigPath = () => join(carrierHome(), 'config.json');
