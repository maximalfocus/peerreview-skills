#!/usr/bin/env bash
# Verify one /peerreview peer side is reachable, without printing credentials.
# Usage: peer-auth.sh <claude|codex|pi|dsh> [--probe-quota]
set -euo pipefail

side="${1:?side (claude|codex|pi|dsh)}"
probe_quota="${2:-}"

# Subscription peers can be signed in yet out of quota. Send one tiny prompt and treat a
# usage-limit reply as unreachable, so select-peer.sh falls through to the next tier. Any other
# probe failure (timeout, network) is not evidence of exhaustion and leaves the peer ready.
# Only peer selection asks for it (--probe-quota); round drivers re-check auth without spending a
# request. PEERREVIEW_QUOTA_PROBE=0 skips the probe.
quota_blocked() {
  [ "$probe_quota" = --probe-quota ] && [ "${PEERREVIEW_QUOTA_PROBE:-1}" != 0 ] || return 1
  local out
  out="$(python3 - "$@" <<'PY' 2>&1
import subprocess, sys
try:
    limit = int(__import__("os").environ.get("PEERREVIEW_QUOTA_TIMEOUT", "90"))
    r = subprocess.run(sys.argv[1:], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                       timeout=limit)
    print(r.stdout[-2000:] + r.stderr[-2000:])
except (subprocess.TimeoutExpired, OSError):
    pass
PY
)"
  local pattern="usage limit|session limit|hit your .*limit|quota exceeded"
  printf '%s' "$out" | grep -iqE "$pattern" || return 1
  printf '%s' "$out" | grep -iE "$pattern" | head -n 1 | cut -c1-200
}

case "$side" in
  claude)
    command -v claude >/dev/null 2>&1 || {
      printf 'peerreview: claude CLI not found. Install Claude Code and run `claude auth login`.\n' >&2
      exit 69
    }
    auth_json="$(claude auth status 2>/dev/null)" || {
      printf 'peerreview: Claude Code is not logged in (run `claude auth login` and sign in with your Claude subscription).\n' >&2
      exit 69
    }
    CLAUDE_AUTH_JSON="$auth_json" python3 - <<'PY' || {
import json, os, sys
try:
    auth = json.loads(os.environ["CLAUDE_AUTH_JSON"])
except (KeyError, json.JSONDecodeError):
    sys.exit(1)
if not auth.get("loggedIn") or auth.get("authMethod") != "claude.ai":
    sys.exit(1)
PY
      printf 'peerreview: Claude Code is not authenticated with a Claude subscription (run `claude auth login`; raw API-key auth is not this contract).\n' >&2
      exit 69
    }
    if limit="$(quota_blocked claude -p 'Reply with exactly: ok')"; then
      printf 'peerreview: Claude Code subscription is out of quota: %s\n' "$limit" >&2
      exit 69
    fi
    printf 'READY claude subscription\n'
    ;;

  pi)
    command -v pi >/dev/null 2>&1 || {
      printf 'peerreview: pi CLI not found. Install Pi and select a DeepSeek model provider.\n' >&2
      exit 69
    }
    auth_json="$(pi auth check --provider deepseek --json 2>/dev/null)" || {
      printf 'peerreview: Pi is not authenticated with a DeepSeek provider (set the DeepSeek API key and select a DeepSeek model in Pi).\n' >&2
      exit 69
    }
    PI_AUTH_JSON="$auth_json" python3 - <<'PY' || {
import json, os, sys
try:
    auth = json.loads(os.environ["PI_AUTH_JSON"])
except (KeyError, json.JSONDecodeError):
    sys.exit(1)
if auth.get("status") != "ready" or auth.get("provider") != "deepseek" or auth.get("authType") != "api_key":
    sys.exit(1)
PY
      printf 'peerreview: Pi provider deepseek is not ready with an API key (set DEEPSEEK_API_KEY or run Pi /login and select DeepSeek).\n' >&2
      exit 69
    }
    printf 'READY pi deepseek api_key\n'
    ;;

  codex)
    command -v codex >/dev/null 2>&1 || {
      printf 'peerreview: Codex CLI not found. Install the Codex CLI and log in with `codex login`.\n' >&2
      exit 69
    }
    # `codex login status` names the auth mode (on stderr) without printing
    # credentials. Capture both streams for version robustness.
    status="$(codex login status 2>&1)" || {
      printf 'peerreview: Codex CLI is not logged in (run `codex login` and sign in with ChatGPT).\n' >&2
      exit 69
    }
    case "$status" in
      *"Logged in using ChatGPT"*)
        if limit="$(quota_blocked codex exec --skip-git-repo-check -s read-only \
            'Reply with exactly: ok')"; then
          printf 'peerreview: Codex CLI subscription is out of quota: %s\n' "$limit" >&2
          exit 69
        fi
        printf 'READY codex chatgpt-subscription\n'
        exit 0
        ;;
    esac
    printf 'peerreview: Codex CLI is not authenticated with an OpenAI ChatGPT subscription (run `codex login`; API-key auth is not this contract).\n' >&2
    exit 69
    ;;

  dsh)
    command -v dsh >/dev/null 2>&1 || {
      printf 'peerreview: DeepSeek Harness (dsh) not found.\n' >&2
      exit 69
    }
    [ -n "${DEEPSEEK_API_KEY:-}" ] || {
      printf 'peerreview: DEEPSEEK_API_KEY is not set for the DeepSeek Harness.\n' >&2
      exit 69
    }
    # Composes the profile tree offline — proves the harness boots without
    # spending a model call or printing the key.
    dsh --profile headless --dump-config >/dev/null 2>&1 || {
      printf 'peerreview: DeepSeek Harness headless profile does not compose (run `dsh --profile headless --dump-config`).\n' >&2
      exit 69
    }
    printf 'READY dsh deepseek api_key\n'
    ;;

  *)
    printf 'peerreview: unsupported auth side: %s (expected claude, codex, pi, or dsh).\n' "$side" >&2
    exit 64
    ;;
esac
