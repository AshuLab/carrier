#!/bin/bash
# Checks the structure rules the tree already meets (spec: docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 9).
# Greps, not a parser: a false alarm is fixed by renaming or by the rule's ignore list, not by a smarter tool.
# Prints `file:line: message` for each violation and exits 1; exits 0 when there is none.
# Each rule is turned on by the change that makes it true, so a rule that is not here is not true yet.
# Run from anywhere; CI runs it in macos/ right after test-ci.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
FAILED=0

# Rule: no two Swift files of one target share a name.
# A target is a folder of Sources/; the same name in two targets is allowed.
# Ignores: files that are not `*.swift`, and the test targets (Tests/ mirrors the sources and is outside this rule).
for target in Sources/*/; do
  find "$target" -name '*.swift' | sort | awk -F/ '
    { name = $NF; files[name] = files[name] " " $0; count[name]++ }
    END { for (n in count) if (count[n] > 1) { split(files[n], list, " "); for (i in list) print list[i] ":1: file name " n " is shared by " count[n] " files of one target" } }' | sort
done > /tmp/check-structure.$$
if [ -s /tmp/check-structure.$$ ]; then
  cat /tmp/check-structure.$$
  FAILED=1
fi
rm -f /tmp/check-structure.$$

exit $FAILED
