import { carrierHome } from '../config/places.ts';
import { addAccount, editAccount, removeAccount, setAccounts, setTextGenerator } from '../config/providers-edit.ts';
import { withEngine } from './engine-reload.ts';
import type { ChatControls } from './server.ts';

/** The five requests that write `providers.json` (ADR 0053), each answering the part it saved and what the engine did with the file. The chat host answers them on its socket and `carrier config` runs them when no host does. */
export const providersRequests = (folder = carrierHome()): Pick<ChatControls, 'setAccounts' | 'addAccount' | 'editAccount' | 'removeAccount' | 'setTextGenerator'> => ({
  setAccounts: ({ accounts }) => withEngine(setAccounts(accounts, folder), folder),
  addAccount: ({ account }) => withEngine(addAccount(account, folder), folder),
  editAccount: ({ name, changes }) => withEngine(editAccount(name, changes, folder), folder),
  removeAccount: ({ name }) => withEngine(removeAccount(name, folder), folder),
  setTextGenerator: ({ choice }) => withEngine(setTextGenerator(choice, folder), folder),
});
