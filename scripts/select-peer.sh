#!/usr/bin/env bash
# Resolve the fixed /peerreview direction from process identity.
set -euo pipefail

if [ "${PI_CODING_AGENT:-}" = "true" ] || [ "${AI_AGENT:-}" = "pi" ]; then
  [ "${PI_PROVIDER:-}" = "openai-codex" ] || {
    printf 'peerreview: Pi HOST must select provider openai-codex; switch the Pi model after /login.\n' >&2
    exit 69
  }
  printf 'HOST=pi PEER=claude DRIVER=claude-round.sh AUTH_SIDE=claude\n'
elif [ -n "${CLAUDECODE:-}" ]; then
  printf 'HOST=claude PEER=pi DRIVER=pi-round.sh AUTH_SIDE=pi\n'
else
  printf 'peerreview: unsupported HOST; run /peerreview inside Pi or Claude Code.\n' >&2
  exit 69
fi
