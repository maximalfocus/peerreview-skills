#!/usr/bin/env bash
# Cross-session Codex rate-limit state.
#
# When any session observes a Codex `ERROR: ...usage limit ... try again at <T>`,
# it records the reset time here. Other sessions read this BEFORE probing Codex
# and, while a limit is active, skip the (hours-long) wait and go straight to the
# disclosed `/code-review` fallback — no per-session re-probe, no user prompt.
#
# State file is deliberately under ~/.claude/state (harness home) so it is shared
# across every Claude Code session and every skill-set (cdd-skills, peerreview-skills),
# not tied to any one repo.
#
# Usage:
#   codex-limit.sh status              -> prints "LIMITED <iso> <mins_left>m" (exit 10)
#                                         or "CLEAR" (exit 0); prunes expired state.
#   codex-limit.sh set <epoch> [reason] [source]
#                                      -> record a reset epoch (seconds).
#   codex-limit.sh set-at "<HH:MM>" [reason] [source]
#                                      -> record reset at the NEXT occurrence of
#                                         HH:MM local (Codex resets roll every ~5h,
#                                         so the reported time is always near-future;
#                                         if HH:MM is already past today it is the
#                                         post-midnight window -> +1 day). Warns if
#                                         the computed reset is >6h out (likely an
#                                         AM/PM mis-parse, since the window is ~5h).
#   codex-limit.sh clear               -> clear state (e.g. after a successful Codex call).
#
# Expiry policy: REMOVE, not ignore. `status` deletes the state file once the
# reset has passed so CLEAR is authoritative and self-healing — a stale-but-present
# file is a cross-session tripwire; the durable audit trail lives in the peerreview
# evolution log, not here.
set -euo pipefail
STATE_DIR="${CODEX_LIMIT_STATE_DIR:-$HOME/.claude/state}"
STATE="$STATE_DIR/codex-limit.json"
mkdir -p "$STATE_DIR"
now=$(date +%s)

read_reset() { [ -f "$STATE" ] && grep -o '"reset_epoch"[ ]*:[ ]*[0-9]*' "$STATE" | grep -o '[0-9]*$' || true; }

case "${1:-status}" in
  status)
    r=$(read_reset)
    if [ -n "$r" ] && [ "$now" -lt "$r" ]; then
      iso=$(date -j -f %s "$r" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d "@$r" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)
      echo "LIMITED $iso $((( (r - now + 59) / 60 )))m"
      exit 10
    fi
    [ -n "$r" ] && rm -f "$STATE"   # prune expired
    echo "CLEAR"; exit 0 ;;
  set)
    r="${2:?epoch required}"; reason="${3:-usage limit}"; source="${4:-unknown}"
    obs=$(date '+%Y-%m-%dT%H:%M:%S%z')
    printf '{\n  "reset_epoch": %s,\n  "reset_iso": "%s",\n  "reason": "%s",\n  "source": "%s",\n  "observed_at": "%s"\n}\n' \
      "$r" "$(date -j -f %s "$r" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d "@$r" '+%Y-%m-%dT%H:%M:%S%z')" \
      "$reason" "$source" "$obs" > "$STATE"
    echo "recorded reset at $r ($STATE)" ;;
  set-at)
    hhmm="${2:?HH:MM required}"; reason="${3:-usage limit}"; source="${4:-unknown}"
    today=$(date '+%Y-%m-%d')
    r=$(date -j -f "%Y-%m-%d %H:%M" "$today $hhmm" +%s 2>/dev/null || date -d "$today $hhmm" +%s)
    [ "$r" -lt "$now" ] && r=$(( r + 86400 ))   # past today -> next (post-midnight) window; resets roll ~5h
    if [ $(( r - now )) -gt 21600 ]; then       # >6h out: window is ~5h, so this looks like an AM/PM mis-parse
      echo "WARN: computed reset is $(( (r-now)/3600 ))h out (>6h); Codex windows are ~5h — check the AM/PM in '$hhmm'." >&2
    fi
    "$0" set "$r" "$reason" "$source" ;;
  clear)
    rm -f "$STATE"; echo "cleared" ;;
  *) echo "usage: $0 {status|set <epoch>|set-at <HH:MM>|clear}" >&2; exit 2 ;;
esac
