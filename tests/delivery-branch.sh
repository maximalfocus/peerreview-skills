#!/usr/bin/env bash
# delivery-branch.sh land: the N-4 subject preflight.
#
# Two properties matter equally here. A refusal must be correct AND must leave
# the reviewed repository untouched — the preflight's whole justification is
# that re-running after a fix costs nothing. And the "must not refuse" cases
# are load-bearing: a false rejection blocks delivery of a finished review in
# a repository peerreview does not own.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/delivery-branch.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/peerreview-land-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

repo="$tmp/repo"
msg="$tmp/msg"

fresh() { # a reviewed repo mid-review: one round commit on peerreview/<slug>
  rm -rf "$repo"; mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name Test
  printf 'base\n' > "$repo/file.txt"
  git -C "$repo" add file.txt; git -C "$repo" commit -qm base
  [ $# -eq 0 ] || { printf '%s' "$1" > "$repo/CLAUDE.md"; git -C "$repo" add CLAUDE.md; git -C "$repo" commit -qm conventions; }
  bash "$script" start "$repo" slug >/dev/null
  printf 'round\n' >> "$repo/file.txt"
  git -C "$repo" commit -qam 'peerreview: round 1'
}

head_before() { git -C "$repo" rev-parse HEAD; }

refuses() { # refuses DESC FRAGMENT
  local desc="$1" frag="$2" before err branch_before
  before="$(head_before)"; branch_before="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
  err="$(bash "$script" land "$repo" slug "$msg" 2>&1 >/dev/null)" && fail "accepted $desc"
  case "$err" in *"$frag"*) ;; *) fail "rejected $desc for the wrong reason: $err" ;; esac
  # The preflight's justification: a rejection mutates nothing.
  [ "$(head_before)" = "$before" ] || fail "$desc: HEAD moved during a refusal"
  [ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" = "$branch_before" ] \
    || fail "$desc: branch changed during a refusal"
  [ -z "$(git -C "$repo" status --porcelain)" ] || fail "$desc: working tree dirtied during a refusal"
}

accepts() { # accepts DESC EXPECTED_SUBJECT
  local desc="$1" want="$2" got
  bash "$script" land "$repo" slug "$msg" >/dev/null || fail "rejected $desc"
  got="$(git -C "$repo" log -1 --format=%s)"
  [ "$got" = "$want" ] || fail "$desc: landed subject was '$got', want '$want'"
}

vocab='# conventions

  Types: `feat` `fix` `docs` `peerreview`
'

# --- must refuse -------------------------------------------------------------
fresh "$vocab"
printf '\n\n' > "$msg"
refuses "a message file with no non-blank line" "no non-blank line"

printf 'feat: %s\n' "$(printf 'x%.0s' $(seq 1 70))" > "$msg"
refuses "a subject over the 72 budget" "over the 72 budget"

printf 'Landed the review\n' > "$msg"
refuses "a subject with no type" "not '<type>(<scope>)?: <description>'"

printf 'feat(Bad Scope): land the review\n' > "$msg"
refuses "a non-kebab scope" "not '<type>(<scope>)?: <description>'"

printf 'feat: Land the review\n' > "$msg"
refuses "a capitalised description" "starts with a capital"

printf 'chore: land the review\n' > "$msg"
refuses "a type outside the reviewed repo's vocabulary" "is not one the reviewed repository allows"

# --- must NOT refuse ---------------------------------------------------------
# A repo that declares nothing is unconstrained.
fresh
printf 'whatever: land the review\n' > "$msg"
accepts "any type where the reviewed repo declares none" "whatever: land the review"

# A Types: line this parser cannot read is a warning, never a block.
fresh '# conventions

Types: see the contributing guide for the list.
'
printf 'chore: land the review\n' > "$msg"
out="$(bash "$script" land "$repo" slug "$msg" 2>&1)" || fail "blocked on an unparseable vocabulary"
case "$out" in *"could not read it"*) ;; *) fail "no warning for an unparseable vocabulary" ;; esac
[ "$(git -C "$repo" log -1 --format=%s)" = "chore: land the review" ] || fail "unparseable-vocabulary land wrote the wrong subject"

# Leading blank lines: git's cleanup drops them, so the preflight must judge
# the same line git will use as the subject — not line 1.
fresh "$vocab"
printf '\n\nfeat(scope): land the review\n\nBody paragraph.\n' > "$msg"
accepts "a message file with leading blank lines" "feat(scope): land the review"

# A scope, a body, and exactly 72 characters all pass.
fresh "$vocab"
s72="feat: $(printf 'y%.0s' $(seq 1 66))"
[ "${#s72}" -eq 72 ] || fail "test bug: built a ${#s72}-char subject"
printf '%s\n\nEvidence lives in the body, not the subject.\n' "$s72" > "$msg"
accepts "a subject at exactly the 72 budget" "$s72"

# The imperative rule stays prose: a noun phrase is not this script's business.
fresh "$vocab"
printf 'docs: the landed subject rule\n' > "$msg"
accepts "a non-imperative description (prose rule, not scripted)" "docs: the landed subject rule"

# --- the refusal is recoverable: fix the line, re-run, it lands --------------
fresh "$vocab"
printf 'chore: land the review\n' > "$msg"
refuses "a disallowed type" "is not one the reviewed repository allows"
printf 'feat: land the review\n' > "$msg"
accepts "the same review after fixing the subject" "feat: land the review"

echo "delivery-branch.sh land preflight valid"
