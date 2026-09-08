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
#
#   Every driver feeds the peer its prompt on stdin. Bash redirects an
#   asynchronous command's stdin from /dev/null "in the absence of any explicit
#   redirections", so the watchdog path below MUST redirect fd 0 explicitly or
#   the peer is launched with no prompt at all. That failure is near-silent: the
#   peer either errors on an empty prompt or, worse, answers a prompt it never
#   received, and a verdict from a peer that never saw the charter satisfies the
#   convergence contract with nothing. Observed 2026-08-19 on doc-permit: a verdict
#   round returned `No prompt provided via stdin` because this path dropped it.
rd_run() {
  local secs="$1"; shift
  if [ "$secs" = "0" ]; then "$@"; return $?; fi
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi

  # No coreutils: enforce the deadline ourselves rather than dropping it.
  local flag; flag="$(mktemp)"; rm -f "$flag"
  # Fixed fd, not bash 4's `{var}<&0`: macOS ships bash 3.2 and the drivers
  # run under /usr/bin/env bash, so a named-fd form fails at runtime there.
  exec 9<&0
  "$@" <&9 &
  local child=$! killer rc=0
  ( sleep "$secs"; : > "$flag"; kill -TERM "$child" 2>/dev/null
    sleep 5; kill -KILL "$child" 2>/dev/null ) >/dev/null 2>&1 &
  killer=$!
  wait "$child" 2>/dev/null || rc=$?
  # The killer is still inside its grace sleep when wait returns, so its being
  # alive proves nothing; the flag records whether the deadline actually fired.
  if [ -e "$flag" ]; then rc=124; fi
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null || true
  exec 9<&-
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

# rd_require_charter <prompt_file> <round>
#   A --verdict prompt must carry the active charter (templates/PROBLEM.md's
#   "## Acceptance criteria" section, or its "- [ ] ACn" lines). A verdict
#   returned against a prompt that never carried the charter satisfies the
#   convergence contract with nothing — the same failure class as rd_run
#   dropping stdin, reached from the HOST side: on 2026-09-08
#   (tutorial-build-a-ci-runner) a HOST slicing bug shipped a 1.4 KB verdict
#   prompt with no charter, no ACs and no spec, and the PEER returned CONVERGED.
#   Refuse before the peer is launched; exit 65 (EX_DATAERR).
rd_require_charter() {
  local prompt_file="$1" round="${2:-}"
  [ "$round" = "--verdict" ] || return 0
  if grep -Eq '^## Acceptance criteria|^- \[[ xX]\] AC[0-9]+' "$prompt_file"; then return 0; fi
  printf 'peerreview: verdict prompt %s carries no charter (no "## Acceptance criteria" section and no "- [ ] ACn" line) — a verdict against it would prove nothing; refusing to launch the peer.\n' "$prompt_file" >&2
  exit 65
}

# rd_tree_fingerprint
#   Content fingerprint of the working tree (HEAD, porcelain status, tracked
#   diff, untracked file hashes). Fingerprint content, not just `git status`
#   names: under the Path-scoped git policy the tree is already dirty, so an
#   edit to an existing modified file leaves the porcelain status byte-identical.
#   Drivers compare it before/after a read-only verdict; a change is not
#   auto-reverted — the HOST adjudicates it before accepting any verdict.
rd_tree_fingerprint() {
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
