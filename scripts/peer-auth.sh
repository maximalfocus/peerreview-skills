#!/usr/bin/env bash
# Verify the fixed /peerreview pair without printing credentials.
# Usage: peer-auth.sh <pi|claude>
set -euo pipefail

side="${1:?side (pi|claude)}"

case "$side" in
  pi)
    command -v pi >/dev/null 2>&1 || {
      printf 'peerreview: pi CLI not found. Install Pi, run /login, and select the OpenAI ChatGPT subscription.\n' >&2
      exit 69
    }
    auth_json="$(pi auth check --provider openai-codex --json 2>/dev/null)" || {
      printf 'peerreview: Pi is not authenticated with an OpenAI ChatGPT subscription (run Pi /login and select OpenAI).\n' >&2
      exit 69
    }
    PI_AUTH_JSON="$auth_json" python3 - <<'PY' || {
import json, os, sys
try:
    auth = json.loads(os.environ["PI_AUTH_JSON"])
except (KeyError, json.JSONDecodeError):
    sys.exit(1)
if auth.get("status") != "ready" or auth.get("provider") != "openai-codex" or auth.get("authType") != "oauth":
    sys.exit(1)
PY
      printf 'peerreview: Pi provider openai-codex is not ready with subscription OAuth (run Pi /login and select OpenAI).\n' >&2
      exit 69
    }
    printf 'READY pi openai-codex oauth\n'
    ;;

  claude)
    command -v claude >/dev/null 2>&1 || {
      printf 'peerreview: Claude Code CLI not found. Install Claude Code and log in with Anthropic or configure the DeepSeek model login.\n' >&2
      exit 69
    }

    # A DeepSeek-backed Claude Code process uses Anthropic-compatible endpoint/model
    # variables. Check names and presence only; never print credential values.
    deepseek_marker="${ANTHROPIC_BASE_URL:-}:${ANTHROPIC_MODEL:-}:${ANTHROPIC_DEFAULT_OPUS_MODEL:-}:${ANTHROPIC_DEFAULT_SONNET_MODEL:-}:${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
    case "$(printf '%s' "$deepseek_marker" | tr '[:upper:]' '[:lower:]')" in
      *deepseek*)
        if [ -n "${ANTHROPIC_AUTH_TOKEN:-${ANTHROPIC_API_KEY:-${DEEPSEEK_API_KEY:-}}}" ]; then
          printf 'READY claude deepseek-model\n'
          exit 0
        fi
        ;;
    esac

    auth_json="$(claude auth status --json 2>/dev/null)" || auth_json=""
    CLAUDE_AUTH_JSON="$auth_json" python3 - <<'PY' && {
import json, os, sys
try:
    auth = json.loads(os.environ.get("CLAUDE_AUTH_JSON", ""))
except json.JSONDecodeError:
    sys.exit(1)
method = str(auth.get("authMethod", "")).lower()
if auth.get("loggedIn") is not True or auth.get("apiProvider") != "firstParty":
    sys.exit(1)
if "oauth" not in method and method not in {"claude.ai", "subscription"}:
    sys.exit(1)
PY
      printf 'READY claude anthropic-subscription\n'
      exit 0
    }

    # Gateway variables are often exported only by the user's interactive shell.
    # Probe that shell without echoing values; the round driver will use it too.
    if [ "${PEER_AUTH_LOGIN_SHELL:-0}" != "1" ] && [ -x "${SHELL:-}" ]; then
      shell_mode="$(PEER_AUTH_LOGIN_SHELL=1 "$SHELL" -ic '
        marker="${ANTHROPIC_BASE_URL:-}:${ANTHROPIC_MODEL:-}:${ANTHROPIC_DEFAULT_OPUS_MODEL:-}:${ANTHROPIC_DEFAULT_SONNET_MODEL:-}:${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
        case "$(printf %s "$marker" | tr "[:upper:]" "[:lower:]")" in
          *deepseek*)
            [ -n "${ANTHROPIC_AUTH_TOKEN:-${ANTHROPIC_API_KEY:-${DEEPSEEK_API_KEY:-}}}" ] && printf deepseek-login-shell
            ;;
        esac
      ' 2>/dev/null || true)"
      if [ "$shell_mode" = "deepseek-login-shell" ]; then
        printf 'READY claude deepseek-login-shell\n'
        exit 0
      fi
    fi

    printf 'peerreview: Claude Code is not authenticated. Use native Anthropic subscription login or configure the DeepSeek model login.\n' >&2
    exit 69
    ;;

  *)
    printf 'peerreview: unsupported auth side: %s (expected pi or claude).\n' "$side" >&2
    exit 64
    ;;
esac
