# src/doctor

- `doctor.ts`: the checks.
- `fixes.ts`: the remedy for each failure.
- `detect.ts`: the detector.
  Per harness, the binary found through `resolveBinary` with its version; per account, whether it is signed in; and the local servers that answer.
  It takes its machine as a port and creates no account.

`carrier doctor --json` prints them as one JSON array of `{ name, status, detail?, fix? }` and nothing else, with the same exit code; the macOS app's Health tab runs it.
