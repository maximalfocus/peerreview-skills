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
# Deadline enforcement lives in one shared helper: the previous per-driver
# fallback ran the peer UNBOUNDED whenever coreutils was absent.
. "$script_dir/round-support.sh"
rd_require_charter "$prompt_file" "$round"

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
  # Never record the verdict: as the newest session it would be what the next
  # `resume --last` edit round picks, inheriting read-only and unable to edit
  # (idd-skills 2026-09-11: every round after a verdict had to start --fresh).
  exec_args=(exec -C "$repo_dir" -s read-only --ephemeral)
  [ "${#add_dir_args[@]}" -gt 0 ] && exec_args+=("${add_dir_args[@]}")
elif [ "$round" = "1" ] || [ "$round" = "--fresh" ]; then
  exec_args=(exec -C "$repo_dir" -s workspace-write)
  [ "${#add_dir_args[@]}" -gt 0 ] && exec_args+=("${add_dir_args[@]}")
else
  exec_args=(exec resume --last)
fi
# Publish the report only after the codex process exits. `-o` is written when a
# session's final message lands, and codex can then roll into a second session
# on the same prompt that keeps editing — so `<out>` appearing is not the end of
# the round (2026-09-08 build-redis: the HOST committed at the first report and
# the second session's edits landed during the verdict).
partial="$out.partial"
rm -f "$partial"
exec_args+=(-o "$partial")

# The Codex sandbox denies writes outside the workspace and (on this host)
# network egress, so the PEER cannot reach git remotes or fetch dependencies;
# gates run on the HOST side. Put the target-scoped git guard first on PATH so
# shell git mutations inside the workspace cannot touch the reviewed checkout's
# git state. HOST still audits HEAD/status after the round.
guard_dir="$(bash "$script_dir/git-guard.sh" "$(pwd -P)")"
trap 'rm -rf "$guard_dir"' EXIT
real_git="$(command -v git)"

head_before="$(git rev-parse HEAD 2>/dev/null || printf 'none')"
fingerprint_before="$(rd_tree_fingerprint)"

rc=0
if [ "$round" = "--verdict" ]; then
  {
    printf '%s\n' 'Read-only verdict round: do not edit files and do not run mutating commands. Reading every file and running read-only probes is allowed and expected. Report findings with file:line, then end with the verdict line.'
    cat "$prompt_file"
  } > "$out.prompt"
  prompt_input="$out.prompt"
else
  prompt_input="$prompt_file"
fi
# shellcheck disable=SC2086
PATH="$guard_dir:$PATH" PEERREVIEW_REAL_GIT="$real_git" PEERREVIEW_PROTECTED_REPO="$(pwd -P)" \
  rd_run "$timeout_s" codex "${exec_args[@]}" < "$prompt_input" > "$out.transcript" 2>&1 || rc=$?
if [ "$round" = "--verdict" ]; then rm -f "$out.prompt"; fi
if [ "$rc" -eq 124 ]; then
  printf 'peerreview: Codex round timed out after %ss (override: CODEX_ROUND_TIMEOUT, 0=disable).\n' "$timeout_s" >&2
fi
[ "$rc" -eq 0 ] || { rd_fail "$rc" Codex "$out.transcript"; exit "$rc"; }
[ -s "$partial" ] || { printf 'peerreview: Codex returned no report (see %s).\n' "$out.transcript" >&2; exit 70; }
mv -f "$partial" "$out"

if [ "$round" = "--verdict" ] && [ "$fingerprint_before" != "$(rd_tree_fingerprint)" ]; then
  printf 'peerreview: Codex mutated the repo during a read-only verdict round (HEAD %s -> %s). Not auto-reverted; adjudicate the diff before accepting any verdict.\n' \
    "$head_before" "$(git rev-parse HEAD 2>/dev/null || printf 'none')" >&2
  exit 70
fi
