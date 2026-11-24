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

# Rule: user defaults are read and written only under CarrierCore/Settings/.
# Flags `UserDefaults.standard`, and a call of the defaults' own accessors (set, object, string, bool, integer, double, float, data, array,
# dictionary, stringArray, url, removeObject) with a literal key (`forKey: "`), outside Sources/CarrierCore/Settings/.
# Ignores: comment lines; an injected `defaults: UserDefaults` parameter and its `= .standard` default; `didChangeNotification` observers;
# and `forKey: "` on something that is not the defaults (`removeValue` on a dictionary, `setValue` of key-value coding, `add` on a layer).
# Exclusion list, each with its reason; a file here is not scanned:
#   Sources/CarrierCore/Chat/ChatOptions.swift  the per-session state (`chat.options.<id>`, `chat.commands.<id>`, `chat.agent.<id>`): state of a session, not a preference
# Sparkle's own `SU*` keys are read by Sparkle, no code of the app names them; the last Settings page is `AppPreferences.lastSettingsPage`, under Settings/.
STATE_FILES=("Sources/CarrierCore/Chat/ChatOptions.swift")
grep -rnE 'UserDefaults\.standard|\b(set|object|string|bool|integer|double|float|data|array|dictionary|stringArray|url|removeObject)\(.*forKey: "' Sources --include='*.swift' |
  grep -v '^Sources/CarrierCore/Settings/' |
  grep -vE '^[^:]+:[0-9]+:\s*//' |
  while IFS= read -r hit; do
    file="${hit%%:*}"
    skip=0
    for state in "${STATE_FILES[@]}"; do [ "$file" = "$state" ] && skip=1; done
    [ "$skip" = 0 ] && echo "$hit" | sed -E 's/^([^:]+:[0-9]+):.*/\1: user defaults are touched outside CarrierCore\/Settings\/: use Preference and AppPreferences/'
  done > /tmp/check-structure-defaults.$$
if [ -s /tmp/check-structure-defaults.$$ ]; then
  cat /tmp/check-structure-defaults.$$
  FAILED=1
fi
rm -f /tmp/check-structure-defaults.$$

exit $FAILED
