#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/peerreview-driver-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/repo"
git -C "$tmp/repo" init -q
git -C "$tmp/repo" config user.email test@example.invalid
git -C "$tmp/repo" config user.name Test
printf 'base\n' > "$tmp/repo/file.txt"
git -C "$tmp/repo" add file.txt
git -C "$tmp/repo" commit -qm base
printf 'review\n' > "$tmp/prompt"

cat > "$tmp/bin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = auth ] && [ "${2:-}" = check ]; then
  case "${PI_FAKE_AUTH:-oauth}" in
    oauth) printf '{"status":"ready","provider":"openai-codex","authType":"oauth"}\n' ;;
    api_key) printf '{"status":"ready","provider":"openai-codex","authType":"api_key"}\n' ;;
    *) exit 1 ;;
  esac
  exit 0
fi
printf '%s\n' "$*" >> "${PI_FAKE_LOG:?}"
cat >/dev/null
[ "${PI_FAKE_RC:-0}" = 0 ] || exit "$PI_FAKE_RC"
if [ "${PI_FAKE_GIT_MUTATE:-0}" = 1 ]; then
  if git commit --allow-empty -m peer-must-not-commit >/dev/null 2>&1; then exit 91; fi
fi
[ "${PI_FAKE_EMPTY:-0}" = 1 ] || printf 'PI_OK\n'
FAKE_PI

cat > "$tmp/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
  case "${CLAUDE_FAKE_AUTH:-native}" in
    native) printf '{"loggedIn":true,"authMethod":"oauth_token","apiProvider":"firstParty"}\n' ;;
    api_key) printf '{"loggedIn":true,"authMethod":"api_key","apiProvider":"firstParty"}\n' ;;
    *) exit 1 ;;
  esac
  exit 0
fi
printf '%s\n' "$*" >> "${CLAUDE_FAKE_LOG:?}"
cat >/dev/null
[ "${CLAUDE_FAKE_RC:-0}" = 0 ] || exit "$CLAUDE_FAKE_RC"
[ "${CLAUDE_FAKE_EMPTY:-0}" = 1 ] || printf 'CLAUDE_OK\n'
FAKE_CLAUDE
chmod +x "$tmp/bin/pi" "$tmp/bin/claude" "$root/scripts/peer-auth.sh" "$root/scripts/select-peer.sh" "$root/scripts/pi-round.sh" "$root/scripts/claude-round.sh"
export PATH="$tmp/bin:$PATH"
export PI_ROUND_TIMEOUT=0 CLAUDE_ROUND_TIMEOUT=0

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -F -- "$2" "$1" >/dev/null || fail "$1 missing: $2"; }
not_contains() { ! grep -F -- "$2" "$1" >/dev/null || fail "$1 unexpectedly contains: $2"; }

# HOST detection is tool-defined and Pi wins even if a nested process inherited
# Claude Code's marker.
selection="$(PI_CODING_AGENT=true AI_AGENT=pi PI_PROVIDER=openai-codex CLAUDECODE=1 "$root/scripts/select-peer.sh")"
[ "$selection" = "HOST=pi PEER=claude DRIVER=claude-round.sh AUTH_SIDE=claude" ] || fail "Pi HOST selection: $selection"
if PI_CODING_AGENT=true PI_PROVIDER=anthropic "$root/scripts/select-peer.sh" >/dev/null 2>&1; then fail "non-OpenAI Pi HOST was accepted"; fi
selection="$(unset PI_CODING_AGENT AI_AGENT PI_PROVIDER; CLAUDECODE=1 "$root/scripts/select-peer.sh")"
[ "$selection" = "HOST=claude PEER=pi DRIVER=pi-round.sh AUTH_SIDE=pi" ] || fail "Claude HOST selection: $selection"
if (unset PI_CODING_AGENT AI_AGENT PI_PROVIDER CLAUDECODE; "$root/scripts/select-peer.sh" >/dev/null 2>&1); then fail "unsupported HOST was accepted"; fi

# Claude HOST -> Pi/OpenAI PEER: fresh, continuation, verdict, auth, output, git guard.
export PI_FAKE_LOG="$tmp/pi.log"
: > "$PI_FAKE_LOG"
"$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi.out" 1
contains "$tmp/pi.out" PI_OK
contains "$PI_FAKE_LOG" "--provider openai-codex"
contains "$PI_FAKE_LOG" "--tools read,write,edit,bash,grep,find,ls"
not_contains "$PI_FAKE_LOG" " -c "

: > "$PI_FAKE_LOG"
"$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi.out" 2
contains "$PI_FAKE_LOG" " -c"

: > "$PI_FAKE_LOG"
"$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi.out" --verdict
contains "$PI_FAKE_LOG" "--tools read,grep,find,ls"
not_contains "$PI_FAKE_LOG" "read,write"

base_head="$(git -C "$tmp/repo" rev-parse HEAD)"
PI_FAKE_GIT_MUTATE=1 "$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi.out" 1
[ "$(git -C "$tmp/repo" rev-parse HEAD)" = "$base_head" ] || fail "Pi peer changed HEAD"

if PI_FAKE_AUTH=api_key "$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi.out" 1 >/dev/null 2>&1; then fail "Pi API-key auth was accepted"; fi
if PI_FAKE_RC=42 "$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi.out" 1 >/dev/null 2>&1; then fail "failed Pi round was accepted"; fi
if PI_FAKE_EMPTY=1 "$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi-empty.out" 1 >/dev/null 2>&1; then fail "empty Pi report was accepted"; fi
if PATH=/usr/bin:/bin "$root/scripts/peer-auth.sh" pi >/dev/null 2>&1; then fail "missing Pi CLI was accepted"; fi

# Pi HOST -> Claude Code PEER: native subscription, continuation, read-only verdict,
# DeepSeek model configuration, auth failure, and non-empty output.
export CLAUDE_FAKE_LOG="$tmp/claude.log"
unset ANTHROPIC_BASE_URL ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY DEEPSEEK_API_KEY || true
: > "$CLAUDE_FAKE_LOG"
"$root/scripts/claude-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/claude.out" 1
contains "$tmp/claude.out" CLAUDE_OK
contains "$CLAUDE_FAKE_LOG" "--permission-mode acceptEdits"
contains "$CLAUDE_FAKE_LOG" "Bash(git commit:*)"
not_contains "$CLAUDE_FAKE_LOG" "--continue"

: > "$CLAUDE_FAKE_LOG"
"$root/scripts/claude-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/claude.out" 2
contains "$CLAUDE_FAKE_LOG" "--continue"

: > "$CLAUDE_FAKE_LOG"
"$root/scripts/claude-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/claude.out" --verdict
contains "$CLAUDE_FAKE_LOG" "--permission-mode plan"
contains "$CLAUDE_FAKE_LOG" "--tools Read,Grep,Glob"

: > "$CLAUDE_FAKE_LOG"
CLAUDE_FAKE_AUTH=none ANTHROPIC_BASE_URL=https://api.deepseek.example/anthropic ANTHROPIC_MODEL=deepseek-chat ANTHROPIC_AUTH_TOKEN=test-only \
  "$root/scripts/claude-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/claude.out" 1
contains "$tmp/claude.out" CLAUDE_OK

if CLAUDE_FAKE_AUTH=none SHELL=/bin/false "$root/scripts/claude-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/claude.out" 1 >/dev/null 2>&1; then fail "unauthenticated Claude was accepted"; fi
if CLAUDE_FAKE_AUTH=api_key SHELL=/bin/false "$root/scripts/claude-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/claude.out" 1 >/dev/null 2>&1; then fail "Claude API-key auth was accepted"; fi
if CLAUDE_FAKE_RC=42 "$root/scripts/claude-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/claude.out" 1 >/dev/null 2>&1; then fail "failed Claude round was accepted"; fi
if CLAUDE_FAKE_EMPTY=1 "$root/scripts/claude-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/claude-empty.out" 1 >/dev/null 2>&1; then fail "empty Claude report was accepted"; fi
if PATH=/usr/bin:/bin "$root/scripts/peer-auth.sh" claude >/dev/null 2>&1; then fail "missing Claude CLI was accepted"; fi

printf 'PASS: round drivers\n'
