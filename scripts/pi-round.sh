#!/usr/bin/env bash
# Drive one Pi/DeepSeek co-edit or read-only verdict round.
# Usage: pi-round.sh <repo_dir> <prompt_file> <last_message_out> [round|--verdict]
set -euo pipefail

repo_dir="${1:?repo_dir}"
prompt_file="${2:?prompt_file}"
out="${3:?last_message_out}"
round="${4:-1}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/peer-auth.sh" pi >/dev/null
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { printf 'peerreview: %s is not a git repo.\n' "$repo_dir" >&2; exit 69; }
[ -f "$prompt_file" ] || { printf 'peerreview: prompt file missing: %s\n' "$prompt_file" >&2; exit 66; }

cd "$repo_dir"

timeout_s="${PI_ROUND_TIMEOUT:-1800}"
TO_CMD=""
if [ "$timeout_s" != "0" ]; then
  if command -v timeout >/dev/null 2>&1; then TO_CMD="timeout $timeout_s"
  elif command -v gtimeout >/dev/null 2>&1; then TO_CMD="gtimeout $timeout_s"
  else printf 'peerreview: no timeout/gtimeout on PATH; running Pi unbounded.\n' >&2; fi
fi

# Keep peer sessions separate from the user's interactive Pi history. A fresh
# round creates the latest session in this repo-specific directory; later rounds
# and the verdict continue it.
repo_key="$(printf '%s' "$repo_dir" | cksum | awk '{print $1}')"
session_dir="${PEERREVIEW_PI_SESSION_DIR:-${TMPDIR:-/tmp}/peerreview-pi-sessions/$repo_key}"
mkdir -p "$session_dir"

# Pin the tier-2 Pi model explicitly so the peer tier is true by construction
# rather than inherited from whatever the provider default happens to be.
args=(-p --provider deepseek --model "${PEERREVIEW_PI_MODEL:-deepseek-v4-flash}"
  --session-dir "$session_dir" --no-extensions --no-skills --no-prompt-templates)
if [ "$round" = "--verdict" ]; then
  args+=(-c --tools read,grep,find,ls --append-system-prompt "Read-only verdict: do not edit files or run commands.")
else
  args+=(--tools read,write,edit,bash,grep,find,ls --append-system-prompt "You are the PEER co-editor. The HOST owns git: never commit, push, change branches/tags/remotes, or rewrite history.")
  if [ "$round" != "1" ] && [ "$round" != "--fresh" ]; then args+=(-c); fi
fi

# Pi intentionally has no permission popups or sandbox. Put a target-scoped git
# guard first on PATH: the PEER may create temporary fixture repos while running
# tests, but flags/env that select where git writes (git-dir, work-tree, index,
# config, object, common-dir, separate-git-dir) cannot target the reviewed
# checkout's git state. Positional targets and direct file writes are out of
# scope; the prompt forbids all remote operations; HOST still audits HEAD/status.
guard_dir="$(bash "$script_dir/git-guard.sh" "$(pwd -P)")"
trap 'rm -rf "$guard_dir"' EXIT
real_git="$(command -v git)"

rc=0
# shellcheck disable=SC2086
PATH="$guard_dir:$PATH" PEERREVIEW_REAL_GIT="$real_git" PEERREVIEW_PROTECTED_REPO="$(pwd -P)" $TO_CMD pi "${args[@]}" < "$prompt_file" > "$out" || rc=$?
if [ "$rc" -eq 124 ]; then
  printf 'peerreview: Pi round timed out after %ss (override: PI_ROUND_TIMEOUT, 0=disable).\n' "$timeout_s" >&2
fi
[ "$rc" -eq 0 ] || exit "$rc"
[ -s "$out" ] || { printf 'peerreview: Pi returned no report.\n' >&2; exit 70; }
