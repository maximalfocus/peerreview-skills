#!/usr/bin/env bash
# delivery-branch.sh land: the N-4 subject preflight, and delivery as a PR.
#
# Three properties matter equally here. A refusal must be correct AND must
# leave the reviewed repository untouched — the preflight's whole justification
# is that re-running after a fix costs nothing. The "must not refuse" cases are
# load-bearing: a false rejection blocks delivery of a finished review in a
# repository peerreview does not own. And a landing never writes the base
# branch (protected since 2026-09-09): the squash goes to evolve/<slug>, that
# branch is pushed, and a pull request is opened — or reused — for it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/delivery-branch.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/peerreview-land-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

repo="$tmp/repo"
origin="$tmp/origin.git"
msg="$tmp/msg"

# Offline gh: records every call, hands back the PR body it was given, and
# answers `pr list` with GH_FAKE_EXISTING (a PR that already exists for the head).
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GH_FAKE_LOG:?}"
case "$1 $2" in
  "pr list") printf '%s\n' "${GH_FAKE_EXISTING:-}" ;;
  "pr create")
    while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "${GH_FAKE_BODY:?}"; shift; done
    printf 'https://example.invalid/pr/1\n' ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
export GH_FAKE_LOG="$tmp/gh.log" GH_FAKE_BODY="$tmp/gh.body"

fresh() { # a reviewed repo mid-review: one round commit on peerreview/<slug>, main pushed to a bare origin
  rm -rf "$repo" "$origin" "$GH_FAKE_LOG" "$GH_FAKE_BODY"; mkdir -p "$repo"
  git init -q --bare "$origin"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name Test
  printf 'base\n' > "$repo/file.txt"
  git -C "$repo" add file.txt; git -C "$repo" commit -qm base
  [ $# -eq 0 ] || { printf '%s' "$1" > "$repo/CLAUDE.md"; git -C "$repo" add CLAUDE.md; git -C "$repo" commit -qm conventions; }
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" push -q -u origin main
  bash "$script" start "$repo" slug >/dev/null
  printf 'round\n' >> "$repo/file.txt"
  git -C "$repo" commit -qam 'peerreview: round 1'
}

head_before() { git -C "$repo" rev-parse HEAD; }
origin_main() { git -C "$origin" rev-parse main; }

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
  [ ! -e "$GH_FAKE_LOG" ] || fail "$desc: gh was called during a refusal"
}

accepts() { # accepts DESC EXPECTED_SUBJECT
  local desc="$1" want="$2" got main_before out
  main_before="$(origin_main)"
  out="$(bash "$script" land "$repo" slug "$msg")" || fail "rejected $desc"
  got="$(git -C "$repo" log -1 --format=%s)"
  [ "$got" = "$want" ] || fail "$desc: landed subject was '$got', want '$want'"
  # The base branch is never written, locally or on origin.
  [ "$(origin_main)" = "$main_before" ] || fail "$desc: origin main moved"
  [ "$(git -C "$repo" rev-parse main)" = "$main_before" ] || fail "$desc: local main moved"
  # The delivery branch holds exactly one squashed commit with the reviewed tree, and is pushed.
  [ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" = evolve/slug ] || fail "$desc: not left on evolve/slug"
  [ "$(git -C "$repo" rev-list --count main..evolve/slug)" = 1 ] || fail "$desc: evolve/slug is not one commit ahead of main"
  git -C "$repo" diff --quiet evolve/slug peerreview/slug || fail "$desc: squashed tree differs from the review branch"
  [ "$(git -C "$origin" rev-parse evolve/slug)" = "$(git -C "$repo" rev-parse evolve/slug)" ] || fail "$desc: evolve/slug not pushed"
  git -C "$repo" rev-parse --verify --quiet peerreview/slug >/dev/null || fail "$desc: review branch was not retained"
  # The PR is opened against the base branch with the subject as title.
  grep -qx "pr create --base main --head evolve/slug --title $want --body-file .*" "$GH_FAKE_LOG" \
    || fail "$desc: no matching pr create in $(cat "$GH_FAKE_LOG")"
  case "$out" in *"https://example.invalid/pr/1"*) ;; *) fail "$desc: PR URL not printed: $out" ;; esac
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

# --- the PR carries the body; a re-run reuses the open PR and the branch -----
fresh "$vocab"
printf '\nfeat: land the review\n\nEvidence: round 1.\n\nKept: everything.\n' > "$msg"
accepts "a message with a body" "feat: land the review"
[ "$(cat "$GH_FAKE_BODY")" = "$(printf 'Evidence: round 1.\n\nKept: everything.')" ] \
  || fail "PR body was not the message body: $(cat "$GH_FAKE_BODY")"
landed="$(git -C "$repo" rev-parse evolve/slug)"
GH_FAKE_EXISTING=https://example.invalid/pr/1 accepts "a re-run after the PR exists" "feat: land the review"
[ "$(git -C "$repo" rev-parse evolve/slug)" = "$landed" ] || fail "re-run re-squashed the delivery branch"
[ "$(grep -c '^pr create' "$GH_FAKE_LOG")" = 1 ] || fail "re-run opened a second PR: $(cat "$GH_FAKE_LOG")"

# A stale delivery branch (different tree) is refused rather than force-pushed over.
fresh "$vocab"
git -C "$repo" branch evolve/slug main
printf 'feat: land the review\n' > "$msg"
err="$(bash "$script" land "$repo" slug "$msg" 2>&1 >/dev/null)" && fail "landed onto a stale evolve/slug"
case "$err" in *"exists but differs"*) ;; *) fail "stale evolve/slug refused for the wrong reason: $err" ;; esac

# The delivery branch must be one land-evolution.sh accepts (N-3 kebab slug).
err="$(bash "$script" land "$repo" Bad_Slug "$msg" 2>&1 >/dev/null)" && fail "accepted a non-kebab slug"
case "$err" in *"lowercase kebab-case"*) ;; *) fail "bad slug refused for the wrong reason: $err" ;; esac

echo "delivery-branch.sh land preflight and PR delivery valid"
