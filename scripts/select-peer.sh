#!/usr/bin/env bash
# Resolve the /peerreview HOST and the highest-tier reachable PEER.
# Usage: select-peer.sh [repo_path]     (repo_path defaults to the cwd)
#
# Tier 1 peers: Claude Code (anthropic) and the Codex CLI (openai).
# Tier 2, only when no tier-1 peer is reachable: the DeepSeek Harness `dsh`
# (deepseek-v4-pro) for CDD-harnessed repos, otherwise Pi (deepseek-v4-flash).
#
# Invariant: PEER vendor != HOST vendor. A same-vendor pass is not a peer
# review — this methodology's own evidence is that degraded same-vendor passes
# miss whole defect families — so a DeepSeek HOST has no tier-2 fallback and
# fails closed instead.
#
# Prints one line on success:
#   HOST=<h> HOST_VENDOR=<v> PEER=<p> PEER_VENDOR=<v> DRIVER=<script> AUTH_SIDE=<p> TIER=<1|2>
set -euo pipefail

repo="${1:-.}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

vendor_of() {
  case "$1" in
    claude) printf 'anthropic' ;;
    codex)  printf 'openai' ;;
    pi|dsh) printf 'deepseek' ;;
    *)      printf 'unknown' ;;
  esac
}

driver_of() {
  case "$1" in
    claude) printf 'claude-round.sh' ;;
    codex)  printf 'codex-round.sh' ;;
    pi)     printf 'pi-round.sh' ;;
    dsh)    printf 'dsh-round.sh' ;;
  esac
}

tier_of() {
  case "$1" in
    claude|codex) printf '1' ;;
    *)            printf '2' ;;
  esac
}

# A CDD-harnessed repo is one Step 1.5 classifies as cdd-prd, cdd-conformance,
# or cdd-implementation — the same file markers, evaluated mechanically here
# because the tier-2 choice must be made before the profile step runs.
cdd_harnessed() {
  local r="$1" base sib m
  [ -d "$r" ] || return 1
  base="$(basename "$(cd "$r" && pwd -P)")"
  case "$base" in *-conformance) return 0 ;; esac
  [ -d "$r/conformance" ] && return 0
  # cdd-prd: PRD.md + at least one PLAN-*.md (idd-prd has PROGRESS.md and no PLAN-*)
  if [ -f "$r/PRD.md" ]; then
    for m in "$r"/PLAN-*.md; do [ -f "$m" ] && return 0; done
  fi
  # cdd-implementation: language manifest + a sibling *-conformance repo
  for m in package.json pom.xml pyproject.toml go.mod Cargo.toml; do
    if [ -f "$r/$m" ]; then
      for sib in "$r"/../*-conformance; do [ -d "$sib" ] && return 0; done
      break
    fi
  done
  return 1
}

# --- HOST identity from process markers (innermost harness wins) -------------
if [ -n "${DSH_SESSION_ID:-}" ] || [ -n "${DSH_HOME:-}" ]; then
  host=dsh
elif [ "${PI_CODING_AGENT:-}" = "true" ] || [ "${AI_AGENT:-}" = "pi" ]; then
  host=pi
  [ "${PI_PROVIDER:-}" = "deepseek" ] || {
    printf 'peerreview: Pi HOST must select provider deepseek (it pins the HOST vendor the peer ladder resolves against); switch the Pi model to a DeepSeek provider.\n' >&2
    exit 69
  }
elif [ -n "${CODEX_CI:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ]; then
  host=codex
elif [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
  host=claude
else
  printf 'peerreview: unsupported HOST; run /peerreview inside Claude Code, the Codex CLI, Pi, or the DeepSeek Harness.\n' >&2
  exit 69
fi
host_vendor="$(vendor_of "$host")"

# --- PEER ladder ------------------------------------------------------------
if cdd_harnessed "$repo"; then tier2=dsh; else tier2=pi; fi
case "$host" in
  claude) ladder="codex $tier2" ;;
  codex)  ladder="claude $tier2" ;;
  pi|dsh) ladder="claude codex" ;;   # tier 2 would be same-vendor: not offered
esac

tried=""
for cand in $ladder; do
  cand_vendor="$(vendor_of "$cand")"
  if [ "$cand_vendor" = "$host_vendor" ]; then
    tried="$tried $cand(same-vendor)"
    continue
  fi
  if reason="$("$script_dir/peer-auth.sh" "$cand" 2>&1 >/dev/null)"; then
    [ -n "$tried" ] && printf 'peerreview: tier-1 peer unavailable (%s); using %s.\n' "${tried# }" "$cand" >&2
    printf 'HOST=%s HOST_VENDOR=%s PEER=%s PEER_VENDOR=%s DRIVER=%s AUTH_SIDE=%s TIER=%s\n' \
      "$host" "$host_vendor" "$cand" "$cand_vendor" "$(driver_of "$cand")" "$cand" "$(tier_of "$cand")"
    exit 0
  fi
  tried="$tried $cand"
  printf 'peerreview: peer candidate %s unavailable: %s\n' "$cand" "$reason" >&2
done

printf 'peerreview: no cross-vendor PEER reachable for HOST=%s (tried:%s). Fail closed — resolve the named blocker and re-run.\n' \
  "$host" "$tried" >&2
exit 69
