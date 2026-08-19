#!/usr/bin/env bash
# Review-on-a-branch delivery: run the loop on a review branch, then land it on
# the delivery branch as ONE squashed commit after the PEER returns CONVERGED.
#
# Standing user preference (2026-08-18/19, asked on three consecutive runs): the
# round-by-round history is review evidence, not product history, so the
# reviewed repo should receive a single reviewed commit.
#
# Usage:
#   delivery-branch.sh start <repo> <slug>          -> create/checkout peerreview/<slug>
#   delivery-branch.sh land  <repo> <slug> <msgfile> -> squash-merge into the base branch
#
# Not applicable when: the repo is under ~/projects (Path-scoped git policy: no
# git writes at all), in --chat mode (ephemeral wrapper, no delivery), or when
# durable intent names an OPEN PR whose head branch is already the review target.
set -euo pipefail
cmd="${1:?start|land}"; repo="${2:?repo}"; slug="${3:?slug}"
cd "$repo"
branch="peerreview/$slug"

case "$cmd" in
  start)
    base="$(git rev-parse --abbrev-ref HEAD)"
    printf '%s\n' "$base" > .git/peerreview-base
    git rev-parse --verify --quiet "$branch" >/dev/null \
      && git checkout -q "$branch" \
      || git checkout -q -b "$branch"
    printf 'peerreview: review branch %s (base %s)\n' "$branch" "$base"
    ;;
  land)
    msgfile="${4:?message file}"
    base="$(cat .git/peerreview-base 2>/dev/null || echo main)"
    [ -z "$(git status --porcelain)" ] || { printf 'peerreview: working tree not clean; commit the last round first.\n' >&2; exit 1; }
    git checkout -q "$base"
    git merge --squash "$branch" >/dev/null
    git commit -q -F "$msgfile"
    printf 'peerreview: squash-merged %s into %s as %s\n' "$branch" "$base" "$(git rev-parse --short HEAD)"
    printf 'peerreview: review branch retained locally with its round commits.\n'
    ;;
  *) printf 'peerreview: unknown command %s\n' "$cmd" >&2; exit 64 ;;
esac
