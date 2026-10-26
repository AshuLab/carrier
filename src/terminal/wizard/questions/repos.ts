import { repoNamePattern } from '../../../config/schema.ts';
import type { Option, Ui } from '../../prompts/types.ts';
import type { InitDeps } from '../deps.ts';

const otherRepo = '\0other';
const loadMore = '\0more';

/** The repos to watch: picked from the ones the gh login can push to (grouped by owner), or typed. */
export async function askRepos(ui: Ui, deps: InitDeps, current: string[] | undefined) {
  const origin = deps.originRepo();
  const suggested = current?.join(', ') ?? origin;
  let listed: string[] = [];
  let hasMore = false;
  try {
    ({ names: listed, hasMore } = deps.listRepos(1));
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
  // a first page emptied by the filter still has later pages while hasMore holds
  if (listed.length === 0 && !hasMore) return typed('Repos to watch (owner/name, comma separated)');

  // What the config already has, or else the folder you are in, goes first and marked, even when it is not among the recent ones; one section per owner.
  const first = current ?? (origin === undefined ? [] : [origin]);
  const other = { value: otherRepo, label: 'Other…', hint: 'type owner/name' };
  let page = 1;
  let ticked = first;
  let picked: string[];
  for (;;) {
    const names = [...first, ...listed.filter((n) => !first.includes(n))];
    const owners = [...new Set(names.map((n) => n.split('/')[0]!))];
    const tail = hasMore ? [{ value: loadMore, label: 'Load more…', hint: 'the next repos' }, other] : [other];
    const groups: Record<string, Option<string>[]> = Object.fromEntries(
      owners.map((owner) => [owner, names.filter((n) => n.startsWith(`${owner}/`)).map((value) => ({ value, label: owners.length > 1 ? value.slice(owner.length + 1) : value }))]),
    );
    if (owners.length === 1) groups[owners[0]!]!.push(...tail);
    else groups.Other = tail;
    picked = await ui.multiselect({ message: 'Repos to watch', options: groups, initialValues: ticked });
    if (!picked.includes(loadMore)) break;
    ticked = picked.filter((n) => n !== loadMore);
    try {
      const next = deps.listRepos(page + 1);
      page += 1;
      hasMore = next.hasMore;
      listed = [...listed, ...next.names.filter((n) => !listed.includes(n))];
    } catch (error) {
      ui.warn(`Could not load more repos (${error instanceof Error ? error.message.split('\n')[0] : String(error)}); going on with the ones loaded.`);
      hasMore = false;
    }
  }
  const chosen = picked.filter((n) => n !== otherRepo);
  const extra = picked.includes(otherRepo) ? await typed('Other repos (owner/name, comma separated)') : [];
  return [...new Set([...chosen, ...extra])];
}
