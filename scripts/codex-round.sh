#!/usr/bin/env bash
# Drive one Codex co-edit round non-interactively, in the target repo.
#
# Usage: codex-round.sh <repo_dir> <prompt_file> <last_message_out> [round]
#
# - <round>: pass "1" (or "--fresh") on the FIRST round of a repo — there is
#   no prior Codex session to resume, and `resume --last` would fail or
#   attach to an unrelated session. Omit / pass "2"+ for later rounds.
# - Round 2+ resumes Codex's most recent session (preserves context).
# - workspace-write sandbox: Codex may edit files but is otherwise contained.
# - Codex MUST NOT commit/push — the reviewer (Claude) owns git. This script
#   does not pass any git capability and the prompt must restate the rule.
# - Fail-closed: aborts if the codex CLI is missing or not authenticated.
set -euo pipefail

repo_dir="${1:?repo_dir}"
prompt_file="${2:?prompt_file}"
out="${3:?last_message_out}"
round="${4:-}"

if ! command -v codex >/dev/null 2>&1; then
  printf 'peerreview: codex CLI not found; cannot run the co-edit loop.\n' >&2
  exit 69
fi
if ! codex login status >/dev/null 2>&1; then
  printf 'peerreview: codex is not authenticated (run: codex login).\n' >&2
  exit 69
fi
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { printf 'peerreview: %s is not a git repo.\n' "$repo_dir" >&2; exit 69; }
[ -f "$prompt_file" ] || { printf 'peerreview: prompt file missing: %s\n' "$prompt_file" >&2; exit 66; }

cd "$repo_dir"

# Bound the round so a stalled `codex exec` can't hang indefinitely. Seen
# 2026-05-28 (urlshortener-cicd-conformance): a workspace-write round wedged
# with the process alive, making no progress and never writing -o, for ~45min
# until a manual kill — wrapping in `timeout` + retrying recovered it. Override
# with CODEX_ROUND_TIMEOUT (seconds; 0 disables). macOS ships GNU timeout as
# `gtimeout` via coreutils. Unquoted $TO_CMD intentionally word-splits and is
# bash-3.2-safe (no empty-array expansion under set -u).
timeout_s="${CODEX_ROUND_TIMEOUT:-1800}"
TO_CMD=""
if [ "$timeout_s" != "0" ]; then
  if command -v timeout >/dev/null 2>&1; then TO_CMD="timeout $timeout_s"
  elif command -v gtimeout >/dev/null 2>&1; then TO_CMD="gtimeout $timeout_s"
  else printf 'peerreview: no timeout/gtimeout on PATH; running codex unbounded.\n' >&2; fi
fi

# Sandbox mode. Default `workspace-write` (Codex may edit the repo, otherwise contained).
# Override with CODEX_SANDBOX — needed where Codex's bwrap sandbox cannot initialise
# (`bwrap: No permissions to create a new namespace`: kernels with unprivileged user
# namespaces disabled, common in containers). That is an ENVIRONMENT block, not a usage
# limit or a transient disconnect; when the workspace is already a trusted container, set
# CODEX_SANDBOX=danger-full-access to run without bwrap rather than falling back to a
# same-vendor review. (2026-06-21 bitmask-typescript.)
sandbox="${CODEX_SANDBOX:-workspace-write}"

# Round 1 (or --fresh): no prior session — start a new one. Round 2+:
# `resume --last` keeps Codex's context. exec options precede the subcommand.
rc=0
if [ "$round" = "1" ] || [ "$round" = "--fresh" ]; then
  $TO_CMD codex exec -s "$sandbox" -o "$out" - < "$prompt_file" || rc=$?
else
  $TO_CMD codex exec -s "$sandbox" -o "$out" resume --last - < "$prompt_file" || rc=$?
fi
if [ "$rc" -eq 124 ]; then
  printf 'peerreview: codex round timed out after %ss (override: CODEX_ROUND_TIMEOUT, 0=disable). Kill stragglers (pkill -f "codex exec") and retry.\n' "$timeout_s" >&2
fi
exit "$rc"
