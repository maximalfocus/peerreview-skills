#!/usr/bin/env bash
# Drive one DeepSeek Harness (dsh) co-edit or read-only verdict round as the PEER.
# Usage: dsh-round.sh <repo_dir> <prompt_file> <last_message_out> [round|--fresh|--verdict]
#
# The tier-2 peer for CDD-harnessed repos; the harness runs its own configured
# model (deepseek-v4-pro by default). Two capability gaps vs the other drivers,
# both handled here rather than in prose:
#   * the headless profile takes the task on argv and has no session resume, so
#     every round is a fresh session — the prompt file must stay self-contained
#     (it already restates the full charter each round);
#   * it has no tool allowlist, so the read-only verdict is enforced by asserting
#     the working tree and HEAD are byte-identical afterwards. A violation fails
#     loudly and is left in place for the HOST to adjudicate — never auto-reverted,
#     because under the Path-scoped git policy the working tree holds the whole review.
set -euo pipefail

repo_dir="${1:?repo_dir}"
prompt_file="${2:?prompt_file}"
out="${3:?last_message_out}"
round="${4:-1}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/peer-auth.sh" dsh >/dev/null
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { printf 'peerreview: %s is not a git repo.\n' "$repo_dir" >&2; exit 69; }
[ -f "$prompt_file" ] || { printf 'peerreview: prompt file missing: %s\n' "$prompt_file" >&2; exit 66; }

cd "$repo_dir"

max_task_bytes="${DSH_ROUND_MAX_TASK_BYTES:-200000}"
task_bytes="$(/usr/bin/wc -c < "$prompt_file" | tr -d ' ')"
[ "$task_bytes" -le "$max_task_bytes" ] || {
  printf 'peerreview: prompt is %s bytes; the dsh headless profile takes the task on argv (limit %s). Trim the round prompt or pick a different peer.\n' \
    "$task_bytes" "$max_task_bytes" >&2
  exit 66
}

timeout_s="${DSH_ROUND_TIMEOUT:-1800}"
TO_CMD=""
if [ "$timeout_s" != "0" ]; then
  if command -v timeout >/dev/null 2>&1; then TO_CMD="timeout $timeout_s"
  elif command -v gtimeout >/dev/null 2>&1; then TO_CMD="gtimeout $timeout_s"
  else printf 'peerreview: no timeout/gtimeout on PATH; running dsh unbounded.\n' >&2; fi
fi

if [ "$round" = "--verdict" ]; then
  preamble='Read-only verdict round: do not edit files and do not run mutating commands. Reading every file is allowed and expected. Return only the verdict.'
else
  preamble='You are the PEER co-editor. Make minimal warranted edits in this repo. The HOST owns git: never commit, push, change branches/tags/remotes, or rewrite history. This session does not carry over between rounds, so treat the brief below as complete.'
fi
task="$preamble"$'\n\n'"$(cat "$prompt_file")"

# Fingerprint content, not just `git status` names: under the Path-scoped git
# policy the tree is already dirty, so an edit to an existing modified file
# leaves the porcelain status byte-identical.
tree_fingerprint() {
  {
    git rev-parse HEAD 2>/dev/null || printf 'none\n'
    git status --porcelain
    git diff HEAD --binary 2>/dev/null || true
    git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
      printf '%s\n' "$f"
      /usr/bin/shasum -a 256 "$f" 2>/dev/null || printf 'unreadable\n'
    done
  } | /usr/bin/shasum -a 256 | awk '{print $1}'
}

head_before="$(git rev-parse HEAD 2>/dev/null || printf 'none')"
fingerprint_before="$(tree_fingerprint)"

# dsh has no permission prompts; put the target-scoped git guard first on PATH so
# shell git mutations cannot touch the reviewed checkout's git state.
guard_dir="$(bash "$script_dir/git-guard.sh" "$(pwd -P)")"
trap 'rm -rf "$guard_dir"' EXIT
real_git="$(command -v git)"

rc=0
# shellcheck disable=SC2086
PATH="$guard_dir:$PATH" PEERREVIEW_REAL_GIT="$real_git" PEERREVIEW_PROTECTED_REPO="$(pwd -P)" \
  $TO_CMD dsh --profile headless "$task" > "$out" 2> "$out.transcript" || rc=$?
if [ "$rc" -eq 124 ]; then
  printf 'peerreview: dsh round timed out after %ss (override: DSH_ROUND_TIMEOUT, 0=disable).\n' "$timeout_s" >&2
fi
[ "$rc" -eq 0 ] || { printf 'peerreview: dsh round failed (see %s).\n' "$out.transcript" >&2; exit "$rc"; }
[ -s "$out" ] || { printf 'peerreview: dsh returned no report (see %s).\n' "$out.transcript" >&2; exit 70; }

if [ "$round" = "--verdict" ]; then
  head_after="$(git rev-parse HEAD 2>/dev/null || printf 'none')"
  if [ "$fingerprint_before" != "$(tree_fingerprint)" ]; then
    printf 'peerreview: dsh mutated the repo during a read-only verdict round (HEAD %s -> %s). Not auto-reverted; adjudicate the diff before accepting any verdict.\n' \
      "$head_before" "$head_after" >&2
    exit 70
  fi
fi
