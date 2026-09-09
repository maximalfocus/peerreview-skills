#!/usr/bin/env bash
# Review-on-a-branch delivery: run the loop on a review branch, then land it as
# ONE squashed commit on a delivery branch, pushed and opened as a pull request
# against the base branch, after the PEER returns CONVERGED.
#
# Standing user preference (2026-08-18/19, asked on three consecutive runs): the
# round-by-round history is review evidence, not product history, so the
# reviewed repo should receive a single reviewed commit. Since 2026-09-09 the
# default branch is protected (PR required, squash only), so `land` never
# writes it: the squashed commit stays on evolve/<slug>, and the merge happens
# only through `~/personal/idd-skills/scripts/land-evolution.sh <PR>` on the
# maintainer's explicit instruction.
#
# Usage:
#   delivery-branch.sh start <repo> <slug>          -> create/checkout peerreview/<slug>
#   delivery-branch.sh land  <repo> <slug> <msgfile> -> squash onto evolve/<slug>, push, open the PR
#
# land preflights the message file's subject against N-4 before touching git.
# The retained repository vocabulary can be broader than land-evolution.sh's
# fixed types; that lander also requires an ASCII lowercase description start.
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
# Tree identity is compared by object id: `git diff --quiet` honours
# diff.ignoreSubmodules and would call two commits equal across a gitlink change.
tree_of() { git rev-parse --verify "$1^{tree}"; }
# The PR body is everything after the subject and its one blank separator; the
# squash merge takes both title and body from the PR, so nothing is lost.
body_of() { awk 'state == 0 && !NF { next } state == 0 { state = 1; next } state == 1 { state = 2; if (!NF) next } { print }' "$1"; }

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

  # Judge the bytes on disk: awk would silently truncate a line at a NUL.
  [ "$(tr -d '\000' < "$msgfile" | wc -c | tr -d ' ')" -eq "$(wc -c < "$msgfile" | tr -d ' ')" ] \
    || reject "the message file contains a NUL byte"
  subject="$(subject_of "$msgfile")"
  [ -n "$subject" ] || reject "the message file has no non-blank line to use as a subject"

  [ "${#subject}" -le 72 ] \
    || reject "the subject is ${#subject} characters, over the 72 budget (N-4): $subject"

  # One line of plain text: a tab or other control character would survive the
  # shape check, be normalised away in the PR title, and never match on re-run.
  case "$subject" in
    *[[:cntrl:]]*) reject "the subject contains a control character (N-4 wants one line of plain text): $subject" ;;
  esac

  printf '%s' "$subject" | grep -qE '^[a-z][a-z0-9]*(\([a-z0-9]+(-[a-z0-9]+)*\))?: .+$' \
    || reject "the subject is not '<type>(<scope>)?: <description>' (N-4): $subject"

  desc="${subject#*: }"
  case "$desc" in
    [[:upper:]]*) reject "the subject's description starts with a capital (N-4 wants lowercase): $subject" ;;
    [a-z]*) ;;
    *) reject "the subject's description must start with a lowercase letter (N-4, and what land-evolution.sh accepts): $subject" ;;
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
# The delivery branch is the N-3 evolve/<slug> that land-evolution.sh accepts.
[[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] \
  || { printf 'peerreview: slug must be lowercase kebab-case (N-3): %s\n' "$slug" >&2; exit 64; }
cd "$repo"
branch="peerreview/$slug"
delivery="evolve/$slug"

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
    # Pinned against user config: status.showUntrackedFiles=no would hide a
    # pending new file, and submodule.<name>.ignore a dirty submodule, from
    # both cleanliness checks.
    tree="$(git status --porcelain --untracked-files=all --ignore-submodules=none)" || { printf 'peerreview: cannot read the working tree state.\n' >&2; exit 1; }
    [ -z "$tree" ] || { printf 'peerreview: working tree not clean; commit the last round first.\n' >&2; exit 1; }
    [ "$base" != "$delivery" ] || { printf 'peerreview: base and delivery branch must differ; restore the base recorded at start.\n' >&2; exit 1; }
    # Ignored files are invisible to status, yet a checkout or squash silently
    # overwrites one whose path the base or reviewed tree tracks and HEAD does
    # not. Refuse that before any write or gh call, and keep the file.
    clobber="$({ git -c core.quotePath=false diff --name-only --diff-filter=A HEAD "refs/heads/$base"
                 git -c core.quotePath=false diff --name-only --diff-filter=A HEAD "refs/heads/$branch"; } | sort -u \
               | while IFS= read -r f; do [ -e "$f" ] && printf '%s\n' "$f"; done; true)"
    [ -z "$clobber" ] || { printf 'peerreview: these paths exist locally but are tracked by the base or reviewed tree and not by HEAD, so landing would overwrite them; move them aside and re-run:\n%s\n' "$clobber" >&2; exit 1; }
    # Resolve branch refs, never a same-named tag. An advanced/diverged base
    # must be reviewed first: merging it here could introduce unreviewed changes.
    base_oid="$(git rev-parse --verify "refs/heads/$base^{commit}")"
    review_oid="$(git rev-parse --verify "refs/heads/$branch^{commit}")"
    git merge-base --is-ancestor "$base_oid" "$review_oid" \
      || { printf 'peerreview: base is not an ancestor of the reviewed head; review the updated base first.\n' >&2; exit 1; }
    # The base branch is never written: the squash lands on the delivery branch.
    # A re-run after a failed push or PR call reuses the delivery branch as long
    # as it is one commit on the base and holds exactly the reviewed tree.
    delivery_oid=""
    if git show-ref --verify --quiet "refs/heads/$delivery"; then
      delivery_oid="$(git rev-parse "refs/heads/$delivery")"
      [ "$(tree_of "$delivery_oid")" = "$(tree_of "$review_oid")" ] \
        || { printf 'peerreview: %s exists but differs from %s; delete or rename it and re-run.\n' "$delivery" "$branch" >&2; exit 1; }
      [ "$(git rev-list --parents -n 1 "$delivery_oid")" = "$delivery_oid $base_oid" ] \
        || { printf 'peerreview: %s must be exactly one non-merge commit on the recorded base; preserve it and use a new slug.\n' "$delivery" >&2; exit 1; }
    fi
    # Check origin before any local write. Unknown remote objects require an
    # explicit fetch first; this refusal itself must not change local refs.
    # Every URL the push would write is the one that was inspected: refuse a
    # remote with several push URLs rather than preflight only the first.
    origin_url="$(git remote get-url --push --all origin)"
    [ "$(printf '%s\n' "$origin_url" | wc -l | tr -d ' ')" -eq 1 ] \
      || { printf 'peerreview: origin has more than one push URL; land delivers to exactly one destination.\n' >&2; exit 1; }
    remote_status=0
    remote_info="$(git ls-remote --exit-code --heads "$origin_url" "refs/heads/$delivery")" || remote_status=$?
    if [ "$remote_status" -eq 0 ]; then
      # ls-remote's pattern matches any ref ENDING in it; take the exact ref only.
      remote_oid="$(printf '%s\n' "$remote_info" | awk -v ref="refs/heads/$delivery" '$2 == ref { print $1; exit }')"
      [ -n "$remote_oid" ] || remote_status=2
    fi
    case "$remote_status" in
      0)
        git cat-file -e "$remote_oid^{commit}" 2>/dev/null \
          || { printf 'peerreview: origin/%s is not available locally; fetch that branch, then re-run.\n' "$delivery" >&2; exit 1; }
        [ "$(tree_of "$remote_oid")" = "$(tree_of "$review_oid")" ] \
          || { printf 'peerreview: origin/%s exists but differs from the reviewed tree; preserve it and use a new slug.\n' "$delivery" >&2; exit 1; }
        [ "$(git rev-list --parents -n 1 "$remote_oid")" = "$remote_oid $base_oid" ] \
          || { printf 'peerreview: origin/%s is not one commit on the recorded base.\n' "$delivery" >&2; exit 1; }
        [ -z "$delivery_oid" ] || [ "$delivery_oid" = "$remote_oid" ] \
          || { printf 'peerreview: local and origin delivery commits differ; preserve both and use a new slug.\n' >&2; exit 1; }
        delivery_oid="$remote_oid" ;;
      2) ;; # no remote branch
      *) printf 'peerreview: cannot inspect origin/%s; nothing changed.\n' "$delivery" >&2; exit 1 ;;
    esac
    # An open PR for the head is inspected before any local write and reused
    # only as it stands: base, title, draft state and body must already be what
    # land-evolution.sh will take. It is never rewritten; else the maintainer
    # decides. gh calls are pinned to origin's push URL, even in a fork checkout
    # where gh's default repository may be the upstream.
    body="$(mktemp "${TMPDIR:-/tmp}/peerreview-pr-body.XXXXXX")"; trap 'rm -f "$body"' EXIT
    body_of "$msgfile" > "$body"
    subject="$(subject_of "$msgfile")"
    pr_url=""
    pr_row="$(gh pr list --repo "$origin_url" --head "$delivery" --state open --json url,isCrossRepository,baseRefName,title,isDraft \
      --jq '[.[] | select(.isCrossRepository == false)][0] | select(. != null) | [.url, .baseRefName, (.isDraft | tostring), .title] | join("\t")')"
    if [ -n "$pr_row" ]; then
      # The free-text title is the last field, so `read` keeps it whole.
      IFS=$'\t' read -r pr_url pr_base pr_draft pr_title <<< "$pr_row"
      pr_body="$(gh pr view "$pr_url" --repo "$origin_url" --json body --jq .body | tr -d '\r')"
      want_body="$(tr -d '\r' < "$body")"
      [ "$pr_body" = "$want_body" ] && body_state=same || body_state=differs
      [ "$pr_base" = "$base" ] && [ "$pr_title" = "$subject" ] && [ "$pr_draft" = false ] && [ "$body_state" = same ] \
        || { printf 'peerreview: the open pull request for %s (%s) is not what the message file describes: base %s (want %s), title "%s" (want "%s"), draft %s (want false), body %s. Fix the PR or the message file, then re-run; nothing was changed.\n' \
               "$delivery" "$pr_url" "$pr_base" "$base" "$pr_title" "$subject" "$pr_draft" "$body_state" >&2; exit 1; }
    fi
    if git show-ref --verify --quiet "refs/heads/$delivery"; then
      git checkout -q --no-overwrite-ignore "$delivery"
    elif [ -n "$delivery_oid" ]; then
      git checkout -q --no-overwrite-ignore -b "$delivery" "$delivery_oid"
    else
      git checkout -q --no-overwrite-ignore -b "$delivery" "$base_oid"
      git merge --squash --no-overwrite-ignore "$review_oid" >/dev/null
      git commit -q -F "$msgfile" || {
        printf 'peerreview: commit failed on %s; staged review changes are retained. Complete the commit with the message file, then re-run land.\n' "$delivery" >&2; exit 1; }
    fi
    # Commit hooks may stage formatting changes or leave edits behind. Do not
    # publish anything except the reviewed tree, even after a successful commit.
    tree="$(git status --porcelain --untracked-files=all --ignore-submodules=none)" || { printf 'peerreview: cannot read the working tree state after the commit; nothing pushed.\n' >&2; exit 1; }
    [ "$(tree_of HEAD)" = "$(tree_of "$review_oid")" ] && [ -z "$tree" ] \
      || { printf 'peerreview: delivery changed during commit; retained locally for review, nothing pushed.\n' >&2; exit 1; }
    printf 'peerreview: squashed %s onto %s as %s (base %s untouched)\n' "$branch" "$delivery" "$(git rev-parse --short HEAD)" "$base"
    git push -q -u origin "refs/heads/$delivery:refs/heads/$delivery"
    if [ -n "$pr_url" ]; then
      printf 'peerreview: reusing the open pull request for %s\n' "$delivery"
    else
      pr_url="$(gh pr create --repo "$origin_url" --base "$base" --head "$delivery" --title "$subject" --body-file "$body")"
    fi
    printf 'peerreview: pull request %s\n' "$pr_url"
    printf 'peerreview: checkout left on %s; review branch retained locally with its round commits.\n' "$delivery"
    printf 'peerreview: merge only via land-evolution.sh <PR> on explicit instruction; never push %s.\n' "$base"
    ;;
  *) printf 'peerreview: unknown command %s\n' "$cmd" >&2; exit 64 ;;
esac
