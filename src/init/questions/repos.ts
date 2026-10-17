import { repoNamePattern } from '../../config/schema.ts';
import type { Option, Ui } from '../../ui/types.ts';
import type { InitDeps } from '../deps.ts';

const otherRepo = '\0other';

/** The repos to watch: picked from the ones the gh login can push to (grouped by owner), or typed. */
export async function askRepos(ui: Ui, deps: InitDeps, current: string[] | undefined) {
  const origin = deps.originRepo();
  const suggested = current?.join(', ') ?? origin;
  let listed: string[] = [];
  try {
    listed = deps.listRepos();
  } catch (error) {
    ui.warn(`Could not list your repos (${error instanceof Error ? error.message.split('\n')[0] : String(error)}); type them instead.`);
  }
  const typed = async (message: string) => {
    const answer = await ui.text({
      message,
      placeholder: suggested ?? 'AshuLab/my-repo',
      defaultValue: suggested,
      validate: (value) => (value.split(',').every((n) => repoNamePattern.test(n.trim())) ? undefined : 'Each repo must be owner/name'),
    });
    return answer.split(',').map((s) => s.trim());
  };
  if (listed.length === 0) return typed('Repos to watch (owner/name, comma separated)');

  // What the config already has, or else the folder you are in, goes first and marked, even when it is not among the recent ones; one section per owner.
  const first = current ?? (origin === undefined ? [] : [origin]);
  const names = [...first, ...listed.filter((n) => !first.includes(n))];
  const owners = [...new Set(names.map((n) => n.split('/')[0]!))];
  const other = { value: otherRepo, label: 'Other…', hint: 'type owner/name' };
  const groups: Record<string, Option<string>[]> = Object.fromEntries(
    owners.map((owner) => [owner, names.filter((n) => n.startsWith(`${owner}/`)).map((value) => ({ value, label: owners.length > 1 ? value.slice(owner.length + 1) : value }))]),
  );
  if (owners.length > 1) groups.Other = [other];
  else groups[owners[0]!]!.push(other);
  const picked = await ui.multiselect({ message: 'Repos to watch', options: groups, initialValues: first });
  const chosen = picked.filter((n) => n !== otherRepo);
  const extra = picked.includes(otherRepo) ? await typed('Other repos (owner/name, comma separated)') : [];
  return [...new Set([...chosen, ...extra])];
}
