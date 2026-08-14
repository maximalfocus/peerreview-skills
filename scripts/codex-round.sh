#!/usr/bin/env bash
# Drive one Codex CLI co-edit round non-interactively in the target repo.
# The tier-1 peer whenever the HOST is not itself the Codex CLI.
# Usage: codex-round.sh <repo_dir> <prompt_file> <last_message_out> [round|--verdict]
# PEERREVIEW_ADD_DIRS (or CODEX_ADD_DIRS) may contain newline-separated external
# evidence directories (granted on the fresh round; the resumed session inherits
# its permissions).
set -euo pipefail

repo_dir="${1:?repo_dir}"
prompt_file="${2:?prompt_file}"
out="${3:?last_message_out}"
round="${4:-1}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/peer-auth.sh" codex >/dev/null
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { printf 'peerreview: %s is not a git repo.\n' "$repo_dir" >&2; exit 69; }
[ -f "$prompt_file" ] || { printf 'peerreview: prompt file missing: %s\n' "$prompt_file" >&2; exit 66; }

cd "$repo_dir"

timeout_s="${CODEX_ROUND_TIMEOUT:-1800}"
TO_CMD=""
if [ "$timeout_s" != "0" ]; then
  if command -v timeout >/dev/null 2>&1; then TO_CMD="timeout $timeout_s"
  elif command -v gtimeout >/dev/null 2>&1; then TO_CMD="gtimeout $timeout_s"
  else printf 'peerreview: no timeout/gtimeout on PATH; running Codex unbounded.\n' >&2; fi
fi

add_dir_args=()
add_dirs="${PEERREVIEW_ADD_DIRS:-${CODEX_ADD_DIRS:-}}"
if [ -n "$add_dirs" ]; then
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    [ -d "$dir" ] || { printf 'peerreview: PEERREVIEW_ADD_DIRS path is not a directory: %s\n' "$dir" >&2; exit 66; }
    add_dir_args+=(--add-dir "$dir")
  done <<< "$add_dirs"
fi

# A fresh round starts a new session with the workspace-write sandbox so the
# PEER can co-edit; later rounds resume that anchored session (cwd-filtered
# `resume --last`, which inherits the session's sandbox). `codex exec resume`
# cannot restrict an anchored session, so the read-only verdict runs in a fresh
# `read-only` sandbox: the PEER can inspect the committed state but cannot edit.
if [ "$round" = "--verdict" ]; then
  exec_args=(exec -C "$repo_dir" -s read-only)
  [ "${#add_dir_args[@]}" -gt 0 ] && exec_args+=("${add_dir_args[@]}")
elif [ "$round" = "1" ] || [ "$round" = "--fresh" ]; then
  exec_args=(exec -C "$repo_dir" -s workspace-write)
  [ "${#add_dir_args[@]}" -gt 0 ] && exec_args+=("${add_dir_args[@]}")
else
  exec_args=(exec resume --last)
fi
exec_args+=(-o "$out")

# The Codex sandbox denies writes outside the workspace and (on this host)
# network egress, so the PEER cannot reach git remotes or fetch dependencies;
# gates run on the HOST side. Put the target-scoped git guard first on PATH so
# shell git mutations inside the workspace cannot touch the reviewed checkout's
# git state. HOST still audits HEAD/status after the round.
guard_dir="$(bash "$script_dir/git-guard.sh" "$(pwd -P)")"
trap 'rm -rf "$guard_dir"' EXIT
real_git="$(command -v git)"

rc=0
if [ "$round" = "--verdict" ]; then
  {
    printf '%s\n' 'Read-only verdict round: do not edit files and do not run commands. Return only the verdict line.'
    cat "$prompt_file"
  } > "$out.prompt"
  prompt_input="$out.prompt"
else
  prompt_input="$prompt_file"
fi
# shellcheck disable=SC2086
PATH="$guard_dir:$PATH" PEERREVIEW_REAL_GIT="$real_git" PEERREVIEW_PROTECTED_REPO="$(pwd -P)" \
  $TO_CMD codex "${exec_args[@]}" < "$prompt_input" > "$out.transcript" 2>&1 || rc=$?
if [ "$round" = "--verdict" ]; then rm -f "$out.prompt"; fi
if [ "$rc" -eq 124 ]; then
  printf 'peerreview: Codex round timed out after %ss (override: CODEX_ROUND_TIMEOUT, 0=disable).\n' "$timeout_s" >&2
fi
[ "$rc" -eq 0 ] || exit "$rc"
[ -s "$out" ] || { printf 'peerreview: Codex returned no report (see %s).\n' "$out.transcript" >&2; exit 70; }
