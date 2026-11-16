#!/bin/bash
# An agent reads an AGENTS.md in full every time it works in its folder, so each one has a budget in bytes (the root one, always read, a tighter one).
# Over budget: cut what it says, or raise the number below in a change a person reviews. Run by CI (Agent context); run it by hand from anywhere in the clone.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT_LIMIT=8500
FOLDER_LIMIT=10000
status=0
while read -r file; do
  size=$(wc -c < "$file" | tr -d ' ')
  limit=$FOLDER_LIMIT
  [ "$file" = AGENTS.md ] && limit=$ROOT_LIMIT
  printf '%6d / %-6d %s\n' "$size" "$limit" "$file"
  if [ "$size" -gt "$limit" ]; then
    echo "::error file=$file::$file is $size bytes, over its budget of $limit: cut what it says, or raise the limit in .github/scripts/agent-context.sh" >&2
    status=1
  fi
done < <(git ls-files '*AGENTS.md')
exit $status
