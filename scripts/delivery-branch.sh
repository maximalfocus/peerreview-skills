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
# land preflights the message file's subject against N-4 before touching git.
#
# Not applicable when: the repo is under ~/projects (Path-scoped git policy: no
# git writes at all), in --chat mode (ephemeral wrapper, no delivery), or when
# durable intent names an OPEN PR whose head branch is already the review target.
set -euo pipefail

# N-4 preflight. The message file's subject becomes the landed commit subject in
# the REVIEWED repository, so it is validated BEFORE any mutation: a rejection
# must leave the checkout exactly as it was, making "fix the line and re-run"
# the whole cost. Shape, budget and vocabulary membership are mechanical
# (CONSTITUTION Article 5); whether the description reads as an imperative is a
# judgment this script deliberately does not make — that rule stays prose.
#
# git's default `whitespace` cleanup for `commit -F` drops leading blank lines,
# so the subject is the first NON-BLANK line, not necessarily line 1.
subject_of() { awk 'NF { print; exit }' "$1"; }

# The reviewed repo owns its vocabulary: the `Types:` line in root AGENTS.md,
# else root CLAUDE.md. A repo declaring none is unconstrained, and so is one
# whose declaration this parser cannot read unambiguously — a review must never
# be blocked by a conventions file it does not own.
# Whether a declaration exists at all is asked separately from what it parses
# to: `declared_types` runs in a command substitution, so a flag set inside it
# would die with that subshell and every unreadable vocabulary would pass
# silently instead of warning.
types_declared() {
  local f
  for f in AGENTS.md CLAUDE.md; do
    [ -f "$f" ] || continue
    if grep -q '^[[:space:]]*Types:' "$f"; then return 0; fi
  done
  return 1
}

declared_types() {
  local f found=""
  for f in AGENTS.md CLAUDE.md; do
    [ -f "$f" ] || continue
    found="$(awk '
      /^[[:space:]]*Types:/ { collecting = 1; sub(/^[[:space:]]*Types:/, ""); }
      collecting && !/^[[:space:]]*Types:/ && $0 !~ /^[[:space:]]*(`[a-z][a-z0-9]*`[[:space:]]*)+$/ { collecting = 0 }
      collecting { print }
    ' "$f" | tr -d '`' | tr -s ' \t' '\n' | grep -E '^[a-z][a-z0-9]*$' || true)"
    [ -n "$found" ] && break
  done
  printf '%s' "$found"
}

reject() {
  printf 'peerreview: refusing to land — %s\n' "$1" >&2
  printf 'peerreview: nothing was changed; fix the message file and re-run.\n' >&2
  exit 65
}

subject_preflight() {
  local msgfile="$1" subject type desc allowed
  [ -r "$msgfile" ] || { printf 'peerreview: cannot read message file: %s\n' "$msgfile" >&2; exit 66; }

  subject="$(subject_of "$msgfile")"
  [ -n "$subject" ] || reject "the message file has no non-blank line to use as a subject"

  [ "${#subject}" -le 72 ] \
    || reject "the subject is ${#subject} characters, over the 72 budget (N-4): $subject"

  printf '%s' "$subject" | grep -qE '^[a-z][a-z0-9]*(\([a-z0-9]+(-[a-z0-9]+)*\))?: .+$' \
    || reject "the subject is not '<type>(<scope>)?: <description>' (N-4): $subject"

  desc="${subject#*: }"
  case "$desc" in
    [[:upper:]]*) reject "the subject's description starts with a capital (N-4 wants lowercase): $subject" ;;
  esac

  type="${subject%%:*}"; type="${type%%(*}"
  allowed="$(declared_types)"
  if [ -n "$allowed" ]; then
    printf '%s\n' "$allowed" | grep -qx -- "$type" \
      || reject "type '$type' is not one the reviewed repository allows: $(printf '%s' "$allowed" | tr '\n' ' ')"
  elif types_declared; then
    printf 'peerreview: the reviewed repo declares Types: but this parser could not read it; leaving the type unconstrained.\n' >&2
  fi
}

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
    subject_preflight "$msgfile"
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
