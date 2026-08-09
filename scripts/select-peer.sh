#!/usr/bin/env bash
# Resolve the fixed /peerreview direction from process identity.
set -euo pipefail

if [ "${PI_CODING_AGENT:-}" = "true" ] || [ "${AI_AGENT:-}" = "pi" ]; then
  [ "${PI_PROVIDER:-}" = "deepseek" ] || {
    printf 'peerreview: Pi HOST must select provider deepseek; switch the Pi model to a DeepSeek provider.\n' >&2
    exit 69
  }
  printf 'HOST=pi PEER=codex DRIVER=codex-round.sh AUTH_SIDE=codex\n'
elif [ -n "${CODEX_CI:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ]; then
  printf 'HOST=codex PEER=pi DRIVER=pi-round.sh AUTH_SIDE=pi\n'
else
  printf 'peerreview: unsupported HOST; run /peerreview inside Pi or the Codex CLI.\n' >&2
  exit 69
fi
