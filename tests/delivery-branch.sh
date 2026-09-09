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
# answers `pr list` with GH_FAKE_EXISTING — the script's own --jq row for a PR
# that already exists for the head: url, base, title, draft, tab-separated.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GH_FAKE_LOG:?}"
[ "${GH_FAKE_FAIL:-}" != "$1 $2" ] || exit 42
case "$1 $2" in
  "pr list") printf '%s\n' "${GH_FAKE_EXISTING:-}" ;;
  "pr create")
    while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "${GH_FAKE_BODY:?}"; shift; done
    printf 'https://example.invalid/pr/1\n' ;;
  "pr view")
    if [ -n "${GH_FAKE_PR_BODY+x}" ]; then printf '%s\n' "$GH_FAKE_PR_BODY"
    elif [ -f "${GH_FAKE_BODY:?}" ]; then cat "$GH_FAKE_BODY"; fi ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
export GH_FAKE_LOG="$tmp/gh.log" GH_FAKE_BODY="$tmp/gh.body"
existing_pr() { printf 'https://example.invalid/pr/1\t%s\t%s\t%s' "${1:-main}" "${3:-false}" "${2:-feat: land the review}"; }

fresh() { # two review rounds: copying the review head must not pass the squash assertion
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
  printf 'round 2\n' >> "$repo/file.txt"
  git -C "$repo" commit -qam 'peerreview: round 2'
}

head_before() { git -C "$repo" rev-parse HEAD; }
origin_main() { git -C "$origin" rev-parse main; }
base_unchanged() {
  [ "$(git -C "$repo" rev-parse main)" = "$base_before" ] || fail "$1: local main moved"
  [ "$(origin_main)" = "$base_before" ] || fail "$1: origin main moved"
}

refuses() { # refuses DESC FRAGMENT
  local desc="$1" frag="$2" before err branch_before slug="${3:-slug}" refs_before tree_before
  before="$(head_before)"; branch_before="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
  refs_before="$(git -C "$repo" show-ref)"; tree_before="$(git -C "$repo" status --porcelain --untracked-files=all --ignore-submodules=none)"
  err="$(bash "$script" land "$repo" "$slug" "$msg" 2>&1 >/dev/null)" && fail "accepted $desc"
  case "$err" in *"$frag"*) ;; *) fail "rejected $desc for the wrong reason: $err" ;; esac
  # The preflight's justification: a rejection mutates nothing.
  [ "$(head_before)" = "$before" ] || fail "$desc: HEAD moved during a refusal"
  [ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" = "$branch_before" ] \
    || fail "$desc: branch changed during a refusal"
  [ "$(git -C "$repo" status --porcelain --untracked-files=all --ignore-submodules=none)" = "$tree_before" ] || fail "$desc: working tree changed during a refusal"
  [ "$(git -C "$repo" show-ref)" = "$refs_before" ] || fail "$desc: refs changed during a refusal"
  [ ! -e "$GH_FAKE_LOG" ] || fail "$desc: gh was called during a refusal"
}

creates() { grep -c '^pr create ' "$GH_FAKE_LOG" 2>/dev/null || true; }

accepts() { # accepts DESC EXPECTED_SUBJECT
  local desc="$1" want="$2" got main_before out creates_before
  main_before="$(origin_main)"; creates_before="$(creates)"; creates_before="${creates_before:-0}"
  out="$(bash "$script" land "$repo" slug "$msg")" || fail "rejected $desc"
  got="$(git -C "$repo" log -1 --format=%s)"
  [ "$got" = "$want" ] || fail "$desc: landed subject was '$got', want '$want'"
  # The base branch is never written, locally or on origin.
  [ "$(origin_main)" = "$main_before" ] || fail "$desc: origin main moved"
  [ "$(git -C "$repo" rev-parse main)" = "$main_before" ] || fail "$desc: local main moved"
  # The delivery branch holds exactly one squashed commit with the reviewed tree, and is pushed.
  [ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" = evolve/slug ] || fail "$desc: not left on evolve/slug"
  [ "$(git -C "$repo" rev-list --count main..evolve/slug)" = 1 ] || fail "$desc: evolve/slug is not one commit ahead of main"
  [ "$(git -C "$repo" rev-parse evolve/slug^{tree})" = "$(git -C "$repo" rev-parse peerreview/slug^{tree})" ] \
    || fail "$desc: squashed tree differs from the review branch"
  [ "$(git -C "$origin" rev-parse evolve/slug)" = "$(git -C "$repo" rev-parse evolve/slug)" ] || fail "$desc: evolve/slug not pushed"
  git -C "$repo" rev-parse --verify --quiet peerreview/slug >/dev/null || fail "$desc: review branch was not retained"
  # The PR is opened against the base branch with the subject as title — once;
  # an existing PR (GH_FAKE_EXISTING) is reused and none is opened.
  if [ -n "${GH_FAKE_EXISTING:-}" ]; then
    [ "$(creates)" = "$creates_before" ] || fail "$desc: opened a PR although one exists: $(cat "$GH_FAKE_LOG")"
  else
    [ "$(creates)" = "$((creates_before + 1))" ] || fail "$desc: expected exactly one new pr create in $(cat "$GH_FAKE_LOG")"
    grep -qx "pr create --repo $origin --base main --head evolve/slug --title $want --body-file .*" "$GH_FAKE_LOG" \
      || fail "$desc: no matching pr create in $(cat "$GH_FAKE_LOG")"
  fi
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

printf 'feat: 123 examples\n' > "$msg"
refuses "a description that does not start with a letter" "start with a lowercase letter"

printf 'feat: keep\ttabs\n' > "$msg"
refuses "a subject with a tab" "control character"

printf 'feat: keep\0nul\n' > "$msg"
refuses "a message file with a NUL byte" "NUL byte"

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
base_before="$(origin_main)"
out="$(bash "$script" land "$repo" slug "$msg" 2>&1)" || fail "blocked on an unparseable vocabulary"
base_unchanged 'unparseable vocabulary'
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
GH_FAKE_EXISTING="$(existing_pr)" accepts "a re-run after the PR exists" "feat: land the review"
[ "$(git -C "$repo" rev-parse evolve/slug)" = "$landed" ] || fail "re-run re-squashed the delivery branch"
[ "$(grep -c '^pr create' "$GH_FAKE_LOG")" = 1 ] || fail "re-run opened a second PR: $(cat "$GH_FAKE_LOG")"

# A stale delivery branch (different tree) is refused rather than force-pushed over.
fresh "$vocab"
git -C "$repo" branch evolve/slug main
printf 'feat: land the review\n' > "$msg"
refuses "a stale evolve/slug" "exists but differs"

# The delivery branch must be one land-evolution.sh accepts (N-3 kebab slug).
refuses "a non-kebab slug" "lowercase kebab-case" Bad_Slug
refuses "a multiline slug" "lowercase kebab-case" $'slug\nBAD'

# A same-tree branch with round history is not a valid prior delivery.
fresh "$vocab"
git -C "$repo" branch evolve/slug peerreview/slug
refuses "an unsquashed same-tree branch" "exactly one non-merge commit"

# Advancing the base with an unrelated file would otherwise silently merge an
# unreviewed change into the delivery tree.
fresh "$vocab"
git -C "$repo" checkout -q main
printf 'unreviewed\n' > "$repo/unreviewed.txt"
git -C "$repo" add unreviewed.txt
git -C "$repo" commit -qm 'fix: advance the base'
git -C "$repo" checkout -q peerreview/slug
refuses "an advanced base" "base is not an ancestor"

fresh "$vocab"
git -C "$repo" branch evolve/slug peerreview/slug
printf 'evolve/slug\n' > "$repo/.git/peerreview-base"
refuses "a base/delivery collision" "base and delivery branch must differ"

# A different-tree remote branch must not be overwritten even when the push
# would be a fast-forward. A valid remote-only squash is reused verbatim.
fresh "$vocab"
git -C "$repo" push -q origin main:refs/heads/evolve/slug
refuses "a stale remote delivery" "exists but differs from the reviewed tree"
[ "$(git -C "$origin" rev-parse evolve/slug)" = "$(origin_main)" ] || fail "stale remote delivery moved"

fresh "$vocab"
printf 'feat: land the review\n' > "$msg"
accepts "initial delivery before remote-only retry" "feat: land the review"
landed="$(git -C "$repo" rev-parse evolve/slug)"
git -C "$repo" checkout -q peerreview/slug
git -C "$repo" branch -D evolve/slug >/dev/null
GH_FAKE_EXISTING="$(existing_pr)" accepts "reuse of remote-only delivery" "feat: land the review"
[ "$(git -C "$repo" rev-parse evolve/slug)" = "$landed" ] || fail "remote delivery re-squashed"

# A provider failure before the first write leaves nothing behind; one after
# the push retains a recoverable delivery. Neither moves either base.
fresh "$vocab"
printf 'feat: land the review\n\nBody.\n' > "$msg"
base_before="$(origin_main)"; refs_before="$(git -C "$repo" show-ref)"
rc=0
GH_FAKE_FAIL='pr list' bash "$script" land "$repo" slug "$msg" >/dev/null 2>&1 || rc=$?
[ "$rc" = 42 ] || fail "pr list: failure was not propagated"
base_unchanged 'pr list failure'
[ "$(git -C "$repo" show-ref)" = "$refs_before" ] || fail "pr list failure wrote refs"
[ "$(git -C "$repo" branch --show-current)" = peerreview/slug ] || fail "pr list failure moved the checkout"
accepts "retry after pr list failure" "feat: land the review"

fresh "$vocab"
printf 'feat: land the review\n\nBody.\n' > "$msg"
base_before="$(origin_main)"
rc=0
GH_FAKE_FAIL='pr create' bash "$script" land "$repo" slug "$msg" >/dev/null 2>&1 || rc=$?
[ "$rc" = 42 ] || fail "pr create: failure was not propagated"
base_unchanged 'pr create failure'
[ -z "$(git -C "$repo" status --porcelain --untracked-files=all --ignore-submodules=none)" ] || fail "pr create: dirty failure state"
landed="$(git -C "$repo" rev-parse evolve/slug)"
accepts "retry after pr create failure" "feat: land the review"
[ "$(git -C "$repo" rev-parse evolve/slug)" = "$landed" ] || fail "pr create: retry re-squashed"

# A same-tree delivery that differs only by a gitlink is still a different
# tree: `git diff --quiet` would call it equal under diff.ignoreSubmodules=all.
fresh "$vocab"
git -C "$repo" config diff.ignoreSubmodules all
git -C "$repo" checkout -q -b evolve/slug main
git -C "$repo" merge -q --squash peerreview/slug >/dev/null
git -C "$repo" commit -qm 'feat: land the review'
git -C "$repo" update-index --add --cacheinfo "160000,$(git -C "$repo" rev-parse HEAD),vendored"
git -C "$repo" commit -q --amend --no-edit
git -C "$repo" checkout -q peerreview/slug
refuses "a delivery differing only by a gitlink" "exists but differs"

# An open PR for the head is reused only as it stands: a title, base, draft
# state or body other than the message file's is reported before any local
# write — from the review branch, with an existing delivery — never rewritten.
for wrong in "main	docs: another title	false	Body." "release	feat: land the review	false	Body." "main	feat: land the review	true	Body." "main	feat: land the review	false	Old evidence."; do
  fresh "$vocab"
  printf 'feat: land the review\n\nBody.\n' > "$msg"
  accepts "initial delivery before a mismatched PR" "feat: land the review"
  git -C "$repo" checkout -q peerreview/slug
  landed="$(git -C "$repo" rev-parse evolve/slug)"; base_before="$(origin_main)"; : > "$GH_FAKE_LOG"
  refs_before="$(git -C "$repo" show-ref)"
  IFS='	' read -r w_base w_title w_draft w_body <<< "$wrong"
  err="$(GH_FAKE_EXISTING="$(existing_pr "$w_base" "$w_title" "$w_draft")" GH_FAKE_PR_BODY="$w_body" bash "$script" land "$repo" slug "$msg" 2>&1 >/dev/null)" \
    && fail "reused a PR with base=$w_base title='$w_title' draft=$w_draft body='$w_body'"
  case "$err" in *"Fix the PR or the message file"*) ;; *) fail "mismatched PR refused for the wrong reason: $err" ;; esac
  base_unchanged 'mismatched PR'
  [ "$(git -C "$repo" show-ref)" = "$refs_before" ] || fail "mismatched PR refusal wrote refs"
  [ "$(git -C "$repo" branch --show-current)" = peerreview/slug ] || fail "mismatched PR refusal moved the checkout"
  [ -z "$(git -C "$repo" status --porcelain --untracked-files=all --ignore-submodules=none)" ] || fail "mismatched PR refusal dirtied the tree"
  [ "$(git -C "$repo" rev-parse evolve/slug)" = "$landed" ] || fail "mismatched PR re-squashed the delivery"
  if grep -q '^pr create ' "$GH_FAKE_LOG"; then fail "mismatched PR led to a second PR"; fi
  if grep -qv '^pr list \|^pr view ' "$GH_FAKE_LOG"; then fail "mismatched PR refusal made a non-read-only gh call: $(cat "$GH_FAKE_LOG")"; fi
done
# The same PR with the same body is reused from the review branch, once.
fresh "$vocab"
printf 'feat: land the review\n\nBody.\n' > "$msg"
accepts "initial delivery before a matching reuse" "feat: land the review"
git -C "$repo" checkout -q peerreview/slug
landed="$(git -C "$repo" rev-parse evolve/slug)"; : > "$GH_FAKE_LOG"
GH_FAKE_EXISTING="$(existing_pr)" GH_FAKE_PR_BODY=$'Body.\r' accepts "reuse of a matching PR (CRLF body)" "feat: land the review"
[ "$(git -C "$repo" rev-parse evolve/slug)" = "$landed" ] || fail "matching reuse re-squashed"

# Cleanliness is judged independently of user config: a pending new file
# hidden by status.showUntrackedFiles=no still refuses, before any write and
# before any gh call, and a hook that leaves one behind still blocks the push.
fresh "$vocab"
printf 'feat: land the review\n' > "$msg"
git -C "$repo" config status.showUntrackedFiles no
printf 'pending\n' > "$repo/pending.txt"
refuses "an untracked file hidden by status.showUntrackedFiles=no" "working tree not clean"
rm "$repo/pending.txt"

fresh "$vocab"
base_before="$(origin_main)"
git -C "$repo" config status.showUntrackedFiles no
printf '#!/bin/sh\nprintf leftover > leftover.txt\n' > "$repo/.git/hooks/pre-commit"
chmod +x "$repo/.git/hooks/pre-commit"
if bash "$script" land "$repo" slug "$msg" >/dev/null 2>&1; then fail "published with a hook-created untracked file"; fi
base_unchanged 'hook-created untracked file'
if grep -q '^pr create ' "$GH_FAKE_LOG"; then fail "PR opened with a hook-created untracked file"; fi
if git -C "$origin" show-ref --verify --quiet refs/heads/evolve/slug; then fail "hook-created untracked file was pushed past"; fi

# An ignored local file whose path the base tracks (and the review removed)
# would be silently overwritten by the delivery checkout: refused before any
# write or gh call, with the file intact.
fresh "$vocab"
printf 'feat: land the review\n' > "$msg"
git -C "$repo" checkout -q main
printf 'shared\n' > "$repo/local.txt"; printf 'local.txt\n' > "$repo/.gitignore"
git -C "$repo" add -f local.txt .gitignore; git -C "$repo" commit -qm 'chore: track a file the ignore list also names'
git -C "$repo" push -q origin main
git -C "$repo" checkout -q peerreview/slug
git -C "$repo" merge -q --no-edit main >/dev/null
git -C "$repo" rm -q local.txt; git -C "$repo" commit -qm 'peerreview: round 3'
printf 'my local work\n' > "$repo/local.txt"
[ -z "$(git -C "$repo" status --porcelain --untracked-files=all)" ] || fail "test bug: the ignored file shows in status"
refs_before="$(git -C "$repo" show-ref)"
err="$(bash "$script" land "$repo" slug "$msg" 2>&1 >/dev/null)" && fail "landed over an ignored local file"
case "$err" in *"exist locally"*) ;; *) fail "ignored-file collision refused for the wrong reason: $err" ;; esac
[ "$(cat "$repo/local.txt")" = "my local work" ] || fail "the ignored local file was overwritten"
[ "$(git -C "$repo" show-ref)" = "$refs_before" ] || fail "ignored-file refusal wrote refs"
[ "$(git -C "$repo" branch --show-current)" = peerreview/slug ] || fail "ignored-file refusal moved the checkout"
[ ! -e "$GH_FAKE_LOG" ] || fail "gh was called before the ignored-file refusal"

# The destination that is inspected is the only one the push writes.
fresh "$vocab"
printf 'feat: land the review\n' > "$msg"
git -C "$repo" remote set-url --add --push origin "$origin"
git -C "$repo" remote set-url --add --push origin "$tmp/second.git"
refuses "a remote with two push URLs" "more than one push URL"

# ls-remote's pattern also matches a ref that merely ends in the delivery
# name; only the exact ref counts as an existing delivery.
fresh "$vocab"
printf 'feat: land the review\n' > "$msg"
git -C "$repo" push -q origin main:refs/heads/x/refs/heads/evolve/slug
accepts "a remote ref that merely ends in the delivery name" "feat: land the review"

# A dirty populated submodule hidden by submodule.<name>.ignore=all still
# refuses, before any write and before any gh call.
fresh "$vocab"
printf 'feat: land the review\n' > "$msg"
sub="$tmp/sub"; rm -rf "$sub"; git init -q "$sub"
git -C "$sub" config user.email test@example.invalid; git -C "$sub" config user.name Test
printf 'lib\n' > "$sub/lib.txt"; git -C "$sub" add lib.txt; git -C "$sub" commit -qm lib
git -C "$repo" -c protocol.file.allow=always submodule add -q "$sub" vendored-sub >/dev/null 2>&1
git -C "$repo" commit -qm 'peerreview: round 3'
git -C "$repo" config submodule.vendored-sub.ignore all
printf 'changed\n' > "$repo/vendored-sub/lib.txt"
refuses "a dirty submodule hidden by submodule.<name>.ignore=all" "working tree not clean"

fresh "$vocab"
printf 'feat: land the review\n' > "$msg"
base_before="$(origin_main)"
printf '#!/bin/sh\nexit 1\n' > "$origin/hooks/pre-receive"
chmod +x "$origin/hooks/pre-receive"
if bash "$script" land "$repo" slug "$msg" >/dev/null 2>&1; then fail "push rejection ignored"; fi
base_unchanged 'push rejection'
if grep -q '^pr create ' "$GH_FAKE_LOG"; then fail "PR opened after a rejected push"; fi
[ -z "$(git -C "$repo" status --porcelain --untracked-files=all --ignore-submodules=none)" ] || fail "push rejection dirtied tree"
landed="$(git -C "$repo" rev-parse evolve/slug)"
rm "$origin/hooks/pre-receive"
accepts "retry after push rejection" "feat: land the review"
[ "$(git -C "$repo" rev-parse evolve/slug)" = "$landed" ] || fail "push retry re-squashed"

fresh "$vocab"
base_before="$(origin_main)"
printf '#!/bin/sh\nexit 1\n' > "$repo/.git/hooks/pre-commit"
chmod +x "$repo/.git/hooks/pre-commit"
if bash "$script" land "$repo" slug "$msg" >/dev/null 2>&1; then fail "commit failure ignored"; fi
base_unchanged 'commit failure'
if grep -q '^pr create ' "$GH_FAKE_LOG"; then fail "PR opened after commit failure"; fi
[ "$(git -C "$repo" branch --show-current)" = evolve/slug ] || fail "commit failure on wrong branch"
git -C "$repo" diff --cached --quiet && fail "commit failure lost staged review"
rm "$repo/.git/hooks/pre-commit"
git -C "$repo" commit -q -F "$msg"
accepts "resume after completing the failed commit" "feat: land the review"

fresh "$vocab"
base_before="$(origin_main)"
cat > "$repo/.git/hooks/pre-commit" <<'HOOK'
#!/bin/sh
printf 'hook formatting\n' >> file.txt
git add file.txt
HOOK
chmod +x "$repo/.git/hooks/pre-commit"
if bash "$script" land "$repo" slug "$msg" >/dev/null 2>&1; then fail "published a hook-altered tree"; fi
base_unchanged 'hook-altered tree'
if grep -q '^pr create ' "$GH_FAKE_LOG"; then fail "PR opened for a hook-altered tree"; fi
if git -C "$origin" show-ref --verify --quiet refs/heads/evolve/slug; then fail "hook-altered tree pushed"; fi

echo "delivery-branch.sh land preflight and PR delivery valid"
