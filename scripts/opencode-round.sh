#!/usr/bin/env bash
# Drive one OpenCode fallback co-edit (or read-only verdict) round.
# Usage: opencode-round.sh <repo_dir> <prompt_file> <last_message_out> [round|--verdict]
set -euo pipefail

repo_dir="${1:?repo_dir}"
prompt_file="${2:?prompt_file}"
out="${3:?last_message_out}"
round="${4:-1}"

command -v opencode >/dev/null 2>&1 || {
  printf 'peerreview: opencode CLI not found; cannot run fallback peer.\n' >&2
  exit 69
}
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { printf 'peerreview: %s is not a git repo.\n' "$repo_dir" >&2; exit 69; }
[ -f "$prompt_file" ] || { printf 'peerreview: prompt file missing: %s\n' "$prompt_file" >&2; exit 66; }

# OpenCode reads a prompt from stdin. Its normal build agent may edit without
# interactive approval; the plan agent denies edits for the verdict pass.
# Git ownership is additionally stated in every prompt and checked by HOST.
timeout_s="${OPENCODE_ROUND_TIMEOUT:-1800}"
TO_CMD=""
if [ "$timeout_s" != "0" ]; then
  if command -v timeout >/dev/null 2>&1; then TO_CMD="timeout $timeout_s"
  elif command -v gtimeout >/dev/null 2>&1; then TO_CMD="gtimeout $timeout_s"
  else printf 'peerreview: no timeout/gtimeout on PATH; running opencode unbounded.\n' >&2; fi
fi

args=(run --dir "$repo_dir")
if [ "$round" = "--verdict" ]; then
  args+=(--continue --agent plan)
elif [ "$round" != "1" ] && [ "$round" != "--fresh" ]; then
  args+=(--continue)
fi

rc=0
# shellcheck disable=SC2086
$TO_CMD opencode "${args[@]}" < "$prompt_file" > "$out" || rc=$?
if [ "$rc" -eq 124 ]; then
  printf 'peerreview: opencode round timed out after %ss (override: OPENCODE_ROUND_TIMEOUT, 0=disable).\n' "$timeout_s" >&2
fi
[ -s "$out" ] || { printf 'peerreview: opencode returned no report.\n' >&2; exit 70; }
exit "$rc"
