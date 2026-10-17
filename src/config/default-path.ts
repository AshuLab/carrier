import { homedir } from 'node:os';
import { join } from 'node:path';

/** Where `carrier init` writes the config and where `carrier` looks when there is no `--config`: global, one per user. */
export const defaultConfigPath = () => join(process.env.CARRIER_HOME ?? join(homedir(), '.carrier'), 'config.json');
