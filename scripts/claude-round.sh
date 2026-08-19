#!/usr/bin/env bash
# Drive one Claude Code co-edit or read-only verdict round as the PEER.
# Usage: claude-round.sh <repo_dir> <prompt_file> <last_message_out> [round|--fresh|--verdict]
# PEERREVIEW_ADD_DIRS (or CODEX_ADD_DIRS) may hold newline-separated external
# evidence directories to grant the PEER read access to.
set -euo pipefail

repo_dir="${1:?repo_dir}"
prompt_file="${2:?prompt_file}"
out="${3:?last_message_out}"
round="${4:-1}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/peer-auth.sh" claude >/dev/null
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { printf 'peerreview: %s is not a git repo.\n' "$repo_dir" >&2; exit 69; }
[ -f "$prompt_file" ] || { printf 'peerreview: prompt file missing: %s\n' "$prompt_file" >&2; exit 66; }

cd "$repo_dir"

timeout_s="${CLAUDE_ROUND_TIMEOUT:-1800}"
# Deadline enforcement lives in one shared helper: the previous per-driver
# fallback ran the peer UNBOUNDED whenever coreutils was absent.
. "$script_dir/round-support.sh"

# Anchor the peer session per repo so rounds 2+ and the verdict continue the
# same conversation, the way the Pi and Codex drivers do.
repo_key="$(printf '%s' "$(pwd -P)" | cksum | awk '{print $1}')"
session_dir="${PEERREVIEW_CLAUDE_SESSION_DIR:-${TMPDIR:-/tmp}/peerreview-claude-sessions}"
mkdir -p "$session_dir"
sid_file="$session_dir/$repo_key"

session_args=()
if [ "$round" = "1" ] || [ "$round" = "--fresh" ]; then
  sid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  printf '%s\n' "$sid" > "$sid_file"
  session_args=(--session-id "$sid")
elif [ -s "$sid_file" ]; then
  session_args=(--resume "$(cat "$sid_file")")
else
  sid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  printf '%s\n' "$sid" > "$sid_file"
  session_args=(--session-id "$sid")
  printf 'peerreview: no anchored Claude session for this repo; starting a fresh one.\n' >&2
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

# --safe-mode keeps the PEER independent of the HOST user's global CLAUDE.md,
# skills, hooks, plugins, and MCP servers; the round prompt carries the charter.
# The read-only verdict denies the mutating tools outright — reading stays
# available and the prompt says so, because a verdict premised on "I may not
# read" is a wrong-premise verdict, not a residual.
cmd_args=(-p --safe-mode --permission-mode bypassPermissions --output-format json)
cmd_args+=("${session_args[@]}")
if [ "$round" = "--verdict" ]; then
  cmd_args+=(--disallowed-tools "Edit Write NotebookEdit Bash"
    --append-system-prompt "Read-only verdict round: do not edit files and do not run commands. Reading every file with your Read/Grep/Glob tools is allowed and expected. Return only the verdict.")
else
  cmd_args+=(--append-system-prompt "You are the PEER co-editor. The HOST owns git: never commit, push, change branches/tags/remotes, or rewrite history.")
fi
# bash 3.2 treats "${empty[@]}" under `set -u` as an unbound variable, so only
# expand the add-dir array when it actually has entries.
[ "${#add_dir_args[@]}" -gt 0 ] && cmd_args+=("${add_dir_args[@]}")

# Claude Code runs with permissions bypassed here, so put the target-scoped git
# guard first on PATH: shell git mutations inside the workspace cannot touch the
# reviewed checkout's git state. HOST still audits HEAD/status after the round.
guard_dir="$(bash "$script_dir/git-guard.sh" "$(pwd -P)")"
trap 'rm -rf "$guard_dir"' EXIT
real_git="$(command -v git)"

rc=0
# shellcheck disable=SC2086
PATH="$guard_dir:$PATH" PEERREVIEW_REAL_GIT="$real_git" PEERREVIEW_PROTECTED_REPO="$(pwd -P)" \
  rd_run "$timeout_s" claude "${cmd_args[@]}" < "$prompt_file" > "$out.transcript" 2>&1 || rc=$?
if [ "$rc" -eq 124 ]; then
  printf 'peerreview: Claude round timed out after %ss (override: CLAUDE_ROUND_TIMEOUT, 0=disable).\n' "$timeout_s" >&2
fi
[ "$rc" -eq 0 ] || { rd_fail "$rc" Claude "$out.transcript"; exit "$rc"; }

CLAUDE_ROUND_JSON="$out.transcript" CLAUDE_ROUND_OUT="$out" python3 - <<'PY' || {
import json, os, sys
try:
    with open(os.environ["CLAUDE_ROUND_JSON"], encoding="utf-8") as fh:
        payload = json.load(fh)
except (OSError, json.JSONDecodeError):
    sys.exit(1)
if payload.get("is_error"):
    sys.exit(1)
result = payload.get("result") or ""
if not result.strip():
    sys.exit(1)
with open(os.environ["CLAUDE_ROUND_OUT"], "w", encoding="utf-8") as fh:
    fh.write(result if result.endswith("\n") else result + "\n")
PY
  printf 'peerreview: Claude returned no report (see %s).\n' "$out.transcript" >&2
  exit 70
}
