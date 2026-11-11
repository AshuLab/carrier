#!/usr/bin/env bash
# The GitHub Release of a version, in the moves of the release order (docs/specs/carrier-updates-itself.md, "The release").
#   draft <version> <file>...    the release as a draft with the files; one that is already there, draft or published, keeps its state and gets its files replaced
#   attach <version> <file>...   the files on the release, replacing the ones with the same name
#   publish <version>            the release is published (already published is not an error)
# `releases/latest` ignores drafts, so until `publish` the update feed still answers with the previous release.
# Needs GH_TOKEN and GITHUB_REPOSITORY in the environment.
set -euo pipefail

command="${1:?usage: github-release.sh draft|attach|publish <version> [file...]}"
tag="v${2:?missing version}"
shift 2

case "$command" in
  draft)
    if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
      gh release upload "$tag" "$@" --clobber --repo "$GITHUB_REPOSITORY"
    else
      # --verify-tag: a draft must not be the one that makes the tag
      gh release create "$tag" "$@" --draft --verify-tag --title "$tag" --generate-notes --repo "$GITHUB_REPOSITORY"
    fi
    ;;
  attach)
    gh release upload "$tag" "$@" --clobber --repo "$GITHUB_REPOSITORY"
    ;;
  publish)
    gh release edit "$tag" --draft=false --repo "$GITHUB_REPOSITORY"
    ;;
  *)
    echo "github-release.sh: unknown command $command" >&2
    exit 1
    ;;
esac
