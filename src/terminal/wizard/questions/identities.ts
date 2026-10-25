import type { Ui } from '../../prompts/types.ts';
import type { Identities } from '../build-config.ts';
import type { InitFlags } from '../flags.ts';

const reach = 'Both roles, the reviewer included, act with everything your gh token can do, as you. Their signature in what they publish is what tells them apart.';

/** Separate identities (a different one per role) or one shared identity, which is the gh login. The first question of the identity step. */
export async function askIdentities(ui: Ui, flags: InitFlags, login: string | undefined, interactive: boolean, current: Identities = 'separate'): Promise<Identities> {
  const { identities: flag } = flags;
  if (flag !== undefined && flag !== 'separate' && flag !== 'shared') throw new Error(`invalid --identities "${flag}", expected separate or shared`);
  const profiles = flags.authorProfile !== undefined || flags.reviewerProfile !== undefined;
  if (flag === 'shared' && profiles) throw new Error('--identities shared cannot go with --author-profile or --reviewer-profile: the shared identity is the gh login');
  for (;;) {
    // A profile flag already names one identity per role, so there is nothing to ask.
    const choice = flag ?? (interactive && !profiles ? await ui.select<Identities>({
      message: 'GitHub identities: one for each role, or one shared?',
      options: [
        { value: 'separate', label: 'One for each role', hint: 'Agent Forge bots, or your gh login for one of them' },
        { value: 'shared', label: 'One shared identity', hint: 'your gh login for both, when you cannot get a second one' },
      ],
      initialValue: current,
    }) : 'separate');
    if (choice === 'separate') return choice;
    if (login === undefined) throw new Error('A shared identity is your gh login, and gh is not logged in. Run: gh auth login');
    ui.note(reach, 'Shared identity');
    if (flag !== undefined || (await ui.confirm('Use your gh login for both roles?'))) return choice; // the flag is the consent
  }
}
