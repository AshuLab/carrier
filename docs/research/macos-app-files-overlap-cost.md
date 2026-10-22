# What the "also in lane" warning costs on a large repository

Measurement for [#158](https://github.com/AshuLab/carrier/issues/158), story 41 of the [macOS app redesign](../specs/macos-app-redesign.md). Method and decision came from [GitHub and git inventory](macos-app-data-github.md) (question 7): intersect the changed paths of the working lanes, no dry-run merge.

## What is measured

`filesOf` (`src/control/files.ts`) on a clone of the largest git repository on this Mac, `/opt/homebrew` (3,428 tracked files, git 2.54, Apple Silicon), with an epic worktree and two lane worktrees. Lane 1 edits 1,500 tracked files and lane 2 edits 1,000, 1,000 of them in both. Nothing is cached: every call asks git again. Three runs each.

| Case | Files changed (lane 1 + lane 2) | Time per request |
|---|---|---|
| 1 file per lane (the floor: git itself) | 1 + 1 | 354 to 371 ms |
| Both lanes at 1,000+ files | 1,500 + 1,000 | 479 to 498 ms |

About 0.12 s separates the two, and that includes git producing the larger diffs and the JSON. The overlap itself is a `Set` of the lanes' paths and a lookup per listed file, so it is not what costs. Most of the time is the fixed git calls (worktree list, merge-base and diff per lane, the log of merges, the total).

## The bound applied

- The overlap is computed over every changed path of each working lane, but only the files kept in the reply carry `alsoIn`. A section lists at most 500 files and a reply 2,000 (`MAX_FILES_PER_SECTION`, `MAX_FILES`), and the reply says `truncated` when it cut. In the run above the reply was 90 KB with 500 files per lane. A file cut from a lane's list is not shown, so its warning is not shown either; the lane's totals still count it.
- Only lanes with a slice branch checked out are compared, and a merged slice is never compared (a merged file is done work, not a clash).
- Untracked files are read for at most 2,000 per lane, 1 MiB each.
- The request is served only when the Files tab asks for it; the snapshot every second does not run it. Half a second per open is acceptable for a tab; if the app ever polls the tab, cache the reply a few seconds (noted in the `ponytail:` comment on `filesOf`).

## Limits

- A path overlap is a hint: two lanes can edit different parts of one file. A dry-run merge (`git merge-tree --write-tree`) was not added; it would see only committed work.
- A rename is the old path leaving and the new path arriving (`--no-renames`), so a lane editing the old name is flagged against the lane that renamed it, and a lane editing the new name against the same. The two lanes do conflict in that case.
- One repository, one machine. A repository with hundreds of thousands of files was not available; the bounds above hold regardless of its size, only git's own time grows.
