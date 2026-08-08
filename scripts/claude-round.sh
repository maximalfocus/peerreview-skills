#!/usr/bin/env bash
# Drive one Claude Code co-edit round non-interactively in the target repo.
# Used when /peerreview runs in Pi; the reverse direction uses pi-round.sh.
# Usage: claude-round.sh <repo_dir> <prompt_file> <last_message_out> [round|--verdict]
# CLAUDE_ADD_DIRS may contain newline-separated external evidence directories.
set -euo pipefail

repo_dir="${1:?repo_dir}"
prompt_file="${2:?prompt_file}"
out="${3:?last_message_out}"
round="${4:-1}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
auth_mode="$("$script_dir/peer-auth.sh" claude)"

git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { printf 'peerreview: %s is not a git repo.\n' "$repo_dir" >&2; exit 69; }
[ -f "$prompt_file" ] || { printf 'peerreview: prompt file missing: %s\n' "$prompt_file" >&2; exit 66; }

add_dir_args=()
if [ -n "${CLAUDE_ADD_DIRS:-}" ]; then
  add_dir_args=(--add-dir)
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    [ -d "$dir" ] || { printf 'peerreview: CLAUDE_ADD_DIRS path is not a directory: %s\n' "$dir" >&2; exit 66; }
    add_dir_args+=("$dir")
  done <<< "$CLAUDE_ADD_DIRS"
  [ "${#add_dir_args[@]}" -gt 1 ] || add_dir_args=()
fi

cd "$repo_dir"
timeout_s="${CLAUDE_ROUND_TIMEOUT:-1800}"
TO_CMD=""
if [ "$timeout_s" != "0" ]; then
  if command -v timeout >/dev/null 2>&1; then TO_CMD="timeout $timeout_s"
  elif command -v gtimeout >/dev/null 2>&1; then TO_CMD="gtimeout $timeout_s"
  else printf 'peerreview: no timeout/gtimeout on PATH; running Claude Code unbounded.\n' >&2; fi
fi

# HOST owns git. Claude may co-edit and run the gate, but git-mutating tools are
# denied and every prompt must restate no commit/push.
DENY_GIT='Bash(git commit:*),Bash(git push:*),Bash(git reset:*),Bash(git revert:*),Bash(git checkout:*),Bash(git switch:*),Bash(git branch:*),Bash(git tag:*),Bash(git fetch:*),Bash(git pull:*),Bash(git merge:*),Bash(git rebase:*),Bash(git cherry-pick:*),Bash(git remote:*),Bash(git config:*)'
claude_args=(claude -p)
if [ "$round" != "1" ] && [ "$round" != "--fresh" ]; then claude_args+=(--continue); fi
if [ "$round" = "--verdict" ]; then
  claude_args+=(--permission-mode plan --tools Read,Grep,Glob)
else
  claude_args+=(--permission-mode acceptEdits)
fi
if [ "${#add_dir_args[@]}" -gt 0 ]; then claude_args+=("${add_dir_args[@]}"); fi
claude_args+=(--disallowedTools "$DENY_GIT")

rc=0
if [ "$auth_mode" = "READY claude deepseek-login-shell" ]; then
  # The DeepSeek endpoint/model credentials exist only in interactive startup.
  # $0 is a harmless label; remaining arguments become "$@" inside the shell.
  # shellcheck disable=SC2086
  $TO_CMD "$SHELL" -ic 'exec "$@"' peerreview "${claude_args[@]}" < "$prompt_file" > "$out" || rc=$?
else
  # shellcheck disable=SC2086
  $TO_CMD "${claude_args[@]}" < "$prompt_file" > "$out" || rc=$?
fi

if [ "$rc" -eq 124 ]; then
  printf 'peerreview: Claude Code round timed out after %ss (override: CLAUDE_ROUND_TIMEOUT, 0=disable).\n' "$timeout_s" >&2
fi
[ "$rc" -eq 0 ] || exit "$rc"
[ -s "$out" ] || { printf 'peerreview: Claude Code returned no report.\n' >&2; exit 70; }
