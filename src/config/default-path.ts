import { homedir } from 'node:os';
import { join } from 'node:path';

/** Carrier's home: `CARRIER_HOME`, else `~/.carrier`. Holds the config, and the chat host's session worktrees. */
export const carrierHome = () => process.env.CARRIER_HOME ?? join(homedir(), '.carrier');

/** Where `carrier init` writes the config and where `carrier` looks when there is no `--config`: global, one per user. */
export const defaultConfigPath = () => join(carrierHome(), 'config.json');
