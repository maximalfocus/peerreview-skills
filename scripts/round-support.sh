#!/usr/bin/env bash
# Portable per-round deadline for the peer-round drivers.
#
# Why this exists: every driver used `timeout`/`gtimeout` and, when neither was
# on PATH, printed a warning and ran the peer UNBOUNDED. On a stock macOS box
# coreutils is absent, so that fallback is the common case, not the rare one —
# a round then has no deadline at all and CODEX_ROUND_TIMEOUT is silently
# inert. Observed 2026-08-18/19: a Codex round ran 3h37m against a flapping
# network before the HOST noticed and killed it by hand, discarding an
# unreported working tree.
#
# rd_run <seconds> <cmd...>
#   0 disables the deadline. Returns the child's exit code, or 124 on timeout —
#   the same convention `timeout` uses, so callers' existing `rc -eq 124`
#   handling keeps working whichever path is taken.
rd_run() {
  local secs="$1"; shift
  if [ "$secs" = "0" ]; then "$@"; return $?; fi
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi

  # No coreutils: enforce the deadline ourselves rather than dropping it.
  local flag; flag="$(mktemp)"; rm -f "$flag"
  "$@" &
  local child=$! killer rc=0
  ( sleep "$secs"; : > "$flag"; kill -TERM "$child" 2>/dev/null
    sleep 5; kill -KILL "$child" 2>/dev/null ) >/dev/null 2>&1 &
  killer=$!
  wait "$child" 2>/dev/null || rc=$?
  # The killer is still inside its grace sleep when wait returns, so its being
  # alive proves nothing; the flag records whether the deadline actually fired.
  if [ -e "$flag" ]; then rc=124; fi
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null || true
  rm -f "$flag"
  return $rc
}

# rd_fail <rc> <peer-label> <transcript-path>
#   A failed round used to surface as a bare non-zero exit with the real cause
#   buried in the transcript: a 2026-08-19 verdict returned exit 1 with a
#   66-byte log while the transcript held repeated DNS failures against the
#   peer API. The HOST had to know to look. Print the tail so the blocker is
#   visible where the failure is reported.
rd_fail() {
  local rc="$1" label="$2" transcript="$3"
  if [ -s "$transcript" ]; then
    printf 'peerreview: %s round failed (rc=%s). Last lines of %s:\n' "$label" "$rc" "$transcript" >&2
    tail -n 12 "$transcript" | sed 's/^/  | /' >&2
  else
    printf 'peerreview: %s round failed (rc=%s); transcript %s is empty.\n' "$label" "$rc" "$transcript" >&2
  fi
}
