#!/usr/bin/env bash
# Verify the fixed /peerreview pair without printing credentials.
# Usage: peer-auth.sh <pi|codex>
set -euo pipefail

side="${1:?side (pi|codex)}"

case "$side" in
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
        printf 'READY codex chatgpt-subscription\n'
        exit 0
        ;;
    esac
    printf 'peerreview: Codex CLI is not authenticated with an OpenAI ChatGPT subscription (run `codex login`; API-key auth is not this contract).\n' >&2
    exit 69
    ;;

  *)
    printf 'peerreview: unsupported auth side: %s (expected pi or codex).\n' "$side" >&2
    exit 64
    ;;
esac
