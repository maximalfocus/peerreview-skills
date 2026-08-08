#!/usr/bin/env bash
# Drive one Claude Code co-edit round non-interactively, in the target repo.
#
# This is the REVERSE-direction mirror of codex-round.sh: used when the HOST
# agent running /peerreview is Codex and the cross-model PEER co-editor is
# Claude Code. (Claude-host → Codex-peer uses codex-round.sh.) Keep the two
# scripts behaviourally parallel — same args, same timeout/fail-closed posture.
#
# Usage: claude-round.sh <repo_dir> <prompt_file> <last_message_out> [round]
#
# - CLAUDE_ADD_DIRS: optional newline-separated absolute directories that the
#   peer must read outside repo_dir (external evidence roots, active charter).
# - <round>: pass "1" (or "--fresh") on the FIRST round of a repo — there is
#   no prior Claude conversation to resume, so we start fresh. Omit / pass
#   "2"+ for later rounds (resumes the most recent conversation in repo_dir,
#   the mirror of codex `resume --last`).
# - Edits are auto-accepted (--permission-mode acceptEdits) and the co-editor
#   may run the verification gate; this is the practical mirror of Codex's
#   `workspace-write` sandbox. ASYMMETRY (documented honestly, not hidden):
#   Codex workspace-write also disables network egress; the claude CLI has no
#   equivalent flag, so the PEER round is NOT network-contained. The real
#   guardrail in both directions is identical: the HOST orchestrator owns git,
#   re-reads the actual diff, and re-runs the gate after the round — never
#   trusting the co-editor's self-report.
# - Claude (as PEER co-editor) MUST NOT commit/push — the HOST orchestrator
#   (here, Codex) owns git. Enforced two ways: git write tools are denied
#   below AND the prompt must restate the rule (parity with codex-round.sh,
#   which relies on the prompt + withholding git capability).
# - Fail-closed: aborts if the claude CLI is missing.
set -euo pipefail

repo_dir="${1:?repo_dir}"
prompt_file="${2:?prompt_file}"
out="${3:?last_message_out}"
round="${4:-}"

# Claude confines tools to the working directory unless external roots are
# explicitly granted. Build one --add-dir group without word-splitting paths.
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

if ! command -v claude >/dev/null 2>&1; then
  printf 'peerreview: claude CLI not found; cannot run the reverse co-edit loop.\n' >&2
  exit 69
fi
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { printf 'peerreview: %s is not a git repo.\n' "$repo_dir" >&2; exit 69; }
[ -f "$prompt_file" ] || { printf 'peerreview: prompt file missing: %s\n' "$prompt_file" >&2; exit 66; }

cd "$repo_dir"

# Bound the round so a stalled `claude -p` can't hang indefinitely (same
# rationale as codex-round.sh). Override with CLAUDE_ROUND_TIMEOUT (seconds;
# 0 disables). macOS ships GNU timeout as `gtimeout` via coreutils.
timeout_s="${CLAUDE_ROUND_TIMEOUT:-1800}"
TO_CMD=""
if [ "$timeout_s" != "0" ]; then
  if command -v timeout >/dev/null 2>&1; then TO_CMD="timeout $timeout_s"
  elif command -v gtimeout >/dev/null 2>&1; then TO_CMD="gtimeout $timeout_s"
  else printf 'peerreview: no timeout/gtimeout on PATH; running claude unbounded.\n' >&2; fi
fi

# Deny git-mutating tools so the PEER cannot commit/push even if it tries;
# the HOST orchestrator owns git. Keep this as one comma-separated argument:
# space-separated shell words split patterns like "Bash(git commit:*)" into
# invalid "Bash(git" fragments before the Claude CLI can parse them.
DENY_GIT='Bash(git commit:*),Bash(git push:*),Bash(git reset:*),Bash(git revert:*)'

# Round 1 (or --fresh): start a new conversation. Round 2+: --continue resumes
# the most recent conversation in repo_dir (mirror of codex `resume --last`).
# Prompt is fed on stdin; the final assistant message is captured to $out.
# A gateway-backed Claude setup may export its provider credentials/model only
# from the user's interactive shell startup file. If the inherited environment
# looks unauthenticated, retry once through that shell before declaring the peer
# unavailable; this supports Anthropic-compatible providers without exposing keys.
# Branch before expanding an empty array: macOS Bash 3 treats
# "${add_dir_args[@]}" as an unbound variable under `set -u` when no external
# evidence roots were supplied.
run_claude() {
  if [ "${#add_dir_args[@]}" -gt 0 ]; then
    # shellcheck disable=SC2086
    $TO_CMD claude -p "$@" --permission-mode acceptEdits "${add_dir_args[@]}" --disallowedTools "$DENY_GIT" < "$prompt_file" > "$out"
  else
    # shellcheck disable=SC2086
    $TO_CMD claude -p "$@" --permission-mode acceptEdits --disallowedTools "$DENY_GIT" < "$prompt_file" > "$out"
  fi
}

rc=0
if [ "$round" = "1" ] || [ "$round" = "--fresh" ]; then
  run_claude || rc=$?
else
  run_claude --continue || rc=$?
fi

# Claude Code accepts Anthropic-compatible gateways (for example DeepSeek), but
# their env may live in ~/.zshrc and therefore be absent from a non-interactive
# coding-agent process. Retry the identical command through $SHELL -ic only for
# the explicit unauthenticated result; never mask a real model/network failure.
if [ "$rc" -ne 0 ] && grep -qi 'not logged in' "$out" 2>/dev/null && [ -x "${SHELL:-}" ]; then
  shell_args=(claude -p)
  if [ "$round" != "1" ] && [ "$round" != "--fresh" ]; then shell_args+=(--continue); fi
  shell_args+=(--permission-mode acceptEdits)
  if [ "${#add_dir_args[@]}" -gt 0 ]; then shell_args+=("${add_dir_args[@]}"); fi
  shell_args+=(--disallowedTools "$DENY_GIT")
  rc=0
  # $0 is a harmless label; remaining arguments become "$@" inside the shell.
  $TO_CMD "$SHELL" -ic 'exec "$@"' peerreview "${shell_args[@]}" < "$prompt_file" > "$out" || rc=$?
fi

if [ "$rc" -eq 124 ]; then
  printf 'peerreview: claude round timed out after %ss (override: CLAUDE_ROUND_TIMEOUT, 0=disable). Kill stragglers (pkill -f "claude -p") and retry.\n' "$timeout_s" >&2
fi
exit "$rc"
