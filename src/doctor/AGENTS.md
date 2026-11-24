# src/doctor

- `doctor.ts`: the checks.
- `fixes.ts`: the remedy for each failure.
- `detect.ts`: the detector.
  Per harness, the binary found through `resolveBinary` with its version; per account, whether it is signed in; and the local servers that answer.
  It takes its machine as a port and creates no account.
- Skills: the doctor asks the `Skills` port (`src/harnesses/skills.ts`, fake in `fake-skills.ts`) whether each skill a role invokes exists for its harness and account, one check per skill.
  Each harness has its reader; one answers `absent` only when it read every place its harness reads.

`carrier doctor --json` prints them as one JSON array of `{ name, status, detail?, detailCode?, detailParams?, fix?, fixCode?, fixParams?, repo?, profiles? }` and nothing else, with the same exit code; the macOS app's Health tab runs it.
Each `detail` and each `fix` is built with its code and params (`fixes.ts` returns them with the words), and the pair is there exactly when its words are.
The words stay as they were; `macos/Tests/Fixtures/doctor.json` is written by `UPDATE_FIXTURES=1 pnpm test` from `doctor-contract.test.ts`, and so is its copy in `macos/DevFixtures`.
