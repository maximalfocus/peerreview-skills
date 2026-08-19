#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/peerreview-driver-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/repo" "$tmp/scratch" "$tmp/scratch2" "$tmp/scratch3"
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
  case "${PI_FAKE_AUTH:-deepseek}" in
    deepseek) printf '{"status":"ready","provider":"deepseek","authType":"api_key"}\n' ;;
    *) exit 1 ;;
  esac
  exit 0
fi
printf '%s\n' "$*" >> "${PI_FAKE_LOG:?}"
cat >/dev/null
[ "${PI_FAKE_RC:-0}" = 0 ] || exit "$PI_FAKE_RC"
if [ -n "${PI_FAKE_GIT_SCRATCH:-}" ]; then
  git -C "$PI_FAKE_GIT_SCRATCH" init -q
  git -C "$PI_FAKE_GIT_SCRATCH" config user.email test@example.invalid
  git -C "$PI_FAKE_GIT_SCRATCH" config user.name Test
  git -C "$PI_FAKE_GIT_SCRATCH" commit --allow-empty -qm fixture
fi
if [ "${PI_FAKE_GIT_MUTATE:-0}" = 1 ]; then
  protected="$PWD"
  if git commit --allow-empty -m peer-must-not-commit >/dev/null 2>&1; then exit 91; fi
  if git update-ref refs/heads/peer-evil HEAD >/dev/null 2>&1; then exit 91; fi
  # Target redirection must not slip past the guard: env, relative paths, and
  # init's command-level --separate-git-dir all target the reviewed repo.
  if GIT_DIR="$protected/.git" GIT_WORK_TREE="$protected" git -C "$protected/../scratch" commit --allow-empty -m peer-env-evil >/dev/null 2>&1; then exit 91; fi
  if git -C "$protected/../scratch" --git-dir ../repo/.git --work-tree "$protected" commit --allow-empty -m peer-path-evil >/dev/null 2>&1; then exit 91; fi
  if (cd "$protected/../scratch" && GIT_DIR=.git GIT_WORK_TREE="$protected" git config peer.evil true >/dev/null 2>&1); then exit 91; fi
  if git -C "$protected/../scratch" init --separate-git-dir "$protected/.git/peer-separate" "$protected/../scratch2" >/dev/null 2>&1; then exit 91; fi
  # clone also takes --separate-git-dir as a command option.
  if git -C "$protected/../scratch" clone --separate-git-dir "$protected/.git/peer-clone" "$protected" "$protected/../scratch2" >/dev/null 2>&1; then exit 91; fi
  # Documented env/file selectors must not redirect writes into the reviewed
  # repo's git state: global/system config files, config --file, the index,
  # the object directory, and the shared common dir of a worktree layout.
  if GIT_CONFIG_GLOBAL="$protected/.git/config" git -C "$protected/../scratch" config --global remote.origin.url https://evil.example/peer >/dev/null 2>&1; then exit 91; fi
  if GIT_CONFIG_SYSTEM="$protected/.git/config" git -C "$protected/../scratch" config --system remote.origin.url https://evil.example/peer >/dev/null 2>&1; then exit 91; fi
  if git -C "$protected/../scratch" config --file "$protected/.git/config" remote.origin.url https://evil.example/peer >/dev/null 2>&1; then exit 91; fi
  if printf 'x\n' > "$protected/../scratch/probe.txt" && GIT_INDEX_FILE="$protected/.git/index" git -C "$protected/../scratch" add probe.txt >/dev/null 2>&1; then exit 91; fi
  if GIT_OBJECT_DIRECTORY="$protected/.git/objects" git -C "$protected/../scratch" commit --allow-empty -m peer-object-evil >/dev/null 2>&1; then exit 91; fi
  if mkdir -p "$protected/../scratch3/evilwt" && printf 'ref: refs/heads/master\n' > "$protected/../scratch3/evilwt/HEAD" && GIT_DIR="$protected/../scratch3/evilwt" GIT_COMMON_DIR="$protected/.git" GIT_WORK_TREE="$protected/../scratch" git -C "$protected/../scratch" commit --allow-empty -m peer-common-evil >/dev/null 2>&1; then exit 91; fi
fi
[ "${PI_FAKE_EMPTY:-0}" = 1 ] || printf 'PI_OK\n'
FAKE_PI

cat > "$tmp/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
  case "${CLAUDE_FAKE_AUTH:-subscription}" in
    subscription) printf '{"loggedIn":true,"authMethod":"claude.ai"}\n' ;;
    apikey) printf '{"loggedIn":true,"authMethod":"apiKey"}\n' ;;
    *) exit 1 ;;
  esac
  exit 0
fi
printf '%s\n' "$*" >> "${CLAUDE_FAKE_LOG:?}"
cat > "${CLAUDE_FAKE_STDIN:-/dev/null}"
[ "${CLAUDE_FAKE_RC:-0}" = 0 ] || exit "$CLAUDE_FAKE_RC"
printf 'CLAUDE_OK\n'
FAKE_CLAUDE

cat > "$tmp/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = login ] && [ "${2:-}" = status ]; then
  case "${CODEX_FAKE_AUTH:-chatgpt}" in
    chatgpt) printf 'Logged in using ChatGPT\n' ;;
    *) exit 1 ;;
  esac
  exit 0
fi
printf '%s\n' "$*" >> "${CODEX_FAKE_LOG:?}"
# The prompt arrives on stdin; keep its first line for verdict assertions.
head -n 1 > "${CODEX_FAKE_STDIN:?}" 2>/dev/null || true
[ "${CODEX_FAKE_RC:-0}" = 0 ] || exit "$CODEX_FAKE_RC"
if [ "${CODEX_FAKE_GIT_MUTATE:-0}" = 1 ]; then
  protected="$PWD"
  if git commit --allow-empty -m peer-must-not-commit >/dev/null 2>&1; then exit 91; fi
  if git update-ref refs/heads/peer-evil HEAD >/dev/null 2>&1; then exit 91; fi
  if GIT_DIR="$protected/.git" GIT_WORK_TREE="$protected" git -C "$protected/../scratch" commit --allow-empty -m peer-env-evil >/dev/null 2>&1; then exit 91; fi
fi
out_file=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out_file="$a"; fi
  prev="$a"
done
[ -z "$out_file" ] || { [ "${CODEX_FAKE_EMPTY:-0}" = 1 ] || printf 'CODEX_OK\n' > "$out_file"; }
FAKE_CODEX
chmod +x "$tmp/bin/pi" "$tmp/bin/codex" "$tmp/bin/claude" "$root/scripts/peer-auth.sh" "$root/scripts/select-peer.sh" "$root/scripts/pi-round.sh" "$root/scripts/codex-round.sh" "$root/scripts/git-guard.sh"
export PATH="$tmp/bin:/usr/bin:/bin"
export PI_ROUND_TIMEOUT=120 CODEX_ROUND_TIMEOUT=120 CLAUDE_ROUND_TIMEOUT=120
# Scrub every HOST marker select-peer.sh consults. Whichever agent runs this
# suite exports its own, and an inherited marker silently changes the detected
# HOST — the same leak class as an unpinned PATH. Each assertion sets exactly
# the markers it is testing.
unset DSH_SESSION_ID DSH_HOME PI_CODING_AGENT AI_AGENT PI_PROVIDER \
      CODEX_CI CODEX_THREAD_ID CLAUDECODE CLAUDE_CODE_ENTRYPOINT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -F -- "$2" "$1" >/dev/null || fail "$1 missing: $2"; }
not_contains() { ! grep -F -- "$2" "$1" >/dev/null || fail "$1 unexpectedly contains: $2"; }

# rd_run's own contract on the no-coreutils watchdog path. This is the path that
# ships by default on stock macOS, and it must not eat the peer's prompt: bash
# redirects an async command's stdin from /dev/null unless fd 0 is redirected
# explicitly, so a regression here launches the peer with no prompt at all and a
# verdict can come back from a model that never saw the charter.
( set +e
  . "$root/scripts/round-support.sh"
  printf 'RD_PROMPT\n' > "$tmp/rd.in"
  got="$(rd_run 30 cat < "$tmp/rd.in")"
  [ "$got" = RD_PROMPT ] || fail "rd_run watchdog path dropped stdin (got: '$got')"
  rd_run 30 sh -c 'exit 42' < "$tmp/rd.in"; [ $? -eq 42 ] || fail "rd_run watchdog path lost the exit code"
  rd_run 1 sleep 5 < "$tmp/rd.in"; [ $? -eq 124 ] || fail "rd_run watchdog path did not report a timeout as 124"
  got="$(rd_run 0 cat < "$tmp/rd.in")"
  [ "$got" = RD_PROMPT ] || fail "rd_run deadline-disabled path dropped stdin (got: '$got')"
) || exit 1

# HOST detection is tool-defined and Pi wins even if a nested process inherited
# the Codex CLI's marker.
selection="$(PI_CODING_AGENT=true AI_AGENT=pi PI_PROVIDER=deepseek CODEX_CI=1 "$root/scripts/select-peer.sh")"
[ "$selection" = "HOST=pi HOST_VENDOR=deepseek PEER=claude PEER_VENDOR=anthropic DRIVER=claude-round.sh AUTH_SIDE=claude TIER=1" ] || fail "Pi HOST selection: $selection"
selection="$(CLAUDE_FAKE_AUTH=none PI_CODING_AGENT=true AI_AGENT=pi PI_PROVIDER=deepseek CODEX_CI=1 "$root/scripts/select-peer.sh")"
[ "$selection" = "HOST=pi HOST_VENDOR=deepseek PEER=codex PEER_VENDOR=openai DRIVER=codex-round.sh AUTH_SIDE=codex TIER=1" ] || fail "Pi HOST tier-1 fallback to Codex: $selection"
if PI_CODING_AGENT=true PI_PROVIDER=anthropic "$root/scripts/select-peer.sh" >/dev/null 2>&1; then fail "non-DeepSeek Pi HOST was accepted"; fi
selection="$(unset PI_CODING_AGENT AI_AGENT PI_PROVIDER; CODEX_CI=1 "$root/scripts/select-peer.sh")"
[ "$selection" = "HOST=codex HOST_VENDOR=openai PEER=claude PEER_VENDOR=anthropic DRIVER=claude-round.sh AUTH_SIDE=claude TIER=1" ] || fail "Codex HOST selection: $selection"
selection="$(unset PI_CODING_AGENT AI_AGENT PI_PROVIDER; CODEX_THREAD_ID=019f-1234 "$root/scripts/select-peer.sh")"
[ "$selection" = "HOST=codex HOST_VENDOR=openai PEER=claude PEER_VENDOR=anthropic DRIVER=claude-round.sh AUTH_SIDE=claude TIER=1" ] || fail "Codex THREAD_ID HOST selection: $selection"
# Tier 2 is reached only when no tier-1 peer authenticates, and is disclosed.
selection="$(unset PI_CODING_AGENT AI_AGENT PI_PROVIDER; CLAUDE_FAKE_AUTH=none CODEX_CI=1 "$root/scripts/select-peer.sh")"
[ "$selection" = "HOST=codex HOST_VENDOR=openai PEER=pi PEER_VENDOR=deepseek DRIVER=pi-round.sh AUTH_SIDE=pi TIER=2" ] || fail "Codex HOST tier-2 fallback: $selection"
# A Claude subscription is the contract; raw API-key auth is not.
selection="$(unset PI_CODING_AGENT AI_AGENT PI_PROVIDER; CLAUDE_FAKE_AUTH=apikey CODEX_CI=1 "$root/scripts/select-peer.sh")"
case "$selection" in *"PEER=claude"*) fail "API-key Claude was accepted as a tier-1 peer: $selection" ;; esac
if (unset PI_CODING_AGENT AI_AGENT PI_PROVIDER CODEX_CI CODEX_THREAD_ID CLAUDECODE CLAUDE_CODE_ENTRYPOINT DSH_SESSION_ID DSH_HOME; "$root/scripts/select-peer.sh" >/dev/null 2>&1); then fail "unsupported HOST was accepted"; fi
# A Claude Code HOST must never be paired with a Claude peer.
selection="$(CLAUDECODE=1 "$root/scripts/select-peer.sh")"
[ "$selection" = "HOST=claude HOST_VENDOR=anthropic PEER=codex PEER_VENDOR=openai DRIVER=codex-round.sh AUTH_SIDE=codex TIER=1" ] || fail "Claude HOST selection: $selection"

# Codex HOST -> Pi/DeepSeek PEER: fresh, continuation, verdict, auth, output, git guard.
export PI_FAKE_LOG="$tmp/pi.log"
: > "$PI_FAKE_LOG"
PI_FAKE_GIT_SCRATCH="$tmp/scratch" "$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi.out" 1
contains "$tmp/pi.out" PI_OK
[ -d "$tmp/scratch/.git" ] || fail "Pi guard blocked a temporary fixture repo"
contains "$PI_FAKE_LOG" "--provider deepseek"
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
if git -C "$tmp/repo" show-ref --verify -q refs/heads/peer-evil; then fail "Pi peer created a branch ref"; fi

if PI_FAKE_AUTH=none "$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi.out" 1 >/dev/null 2>&1; then fail "unauthenticated Pi was accepted"; fi
if PI_FAKE_RC=42 "$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi.out" 1 >/dev/null 2>&1; then fail "failed Pi round was accepted"; fi
if PI_FAKE_EMPTY=1 "$root/scripts/pi-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/pi-empty.out" 1 >/dev/null 2>&1; then fail "empty Pi report was accepted"; fi
if PATH=/usr/bin:/bin "$root/scripts/peer-auth.sh" pi >/dev/null 2>&1; then fail "missing Pi CLI was accepted"; fi

# Pi HOST -> Codex CLI PEER: ChatGPT subscription, fresh exec, continuation,
# read-only verdict, external evidence dirs, auth failure, and non-empty output.
export CODEX_FAKE_LOG="$tmp/codex.log"
export CODEX_FAKE_STDIN="$tmp/codex.stdin"
: > "$CODEX_FAKE_LOG"
"$root/scripts/codex-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/codex.out" 1
contains "$tmp/codex.out" CODEX_OK
contains "$CODEX_FAKE_LOG" "exec"
contains "$CODEX_FAKE_LOG" "-C $tmp/repo"
contains "$CODEX_FAKE_LOG" "-s workspace-write"
contains "$CODEX_FAKE_LOG" "-o $tmp/codex.out"
not_contains "$CODEX_FAKE_LOG" "resume"

: > "$CODEX_FAKE_LOG"
"$root/scripts/codex-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/codex.out" 2
contains "$CODEX_FAKE_LOG" "resume"
contains "$CODEX_FAKE_LOG" "--last"
not_contains "$CODEX_FAKE_LOG" "workspace-write"

: > "$CODEX_FAKE_LOG"
"$root/scripts/codex-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/codex.out" --verdict
contains "$CODEX_FAKE_LOG" "exec"
contains "$CODEX_FAKE_LOG" "-s read-only"
not_contains "$CODEX_FAKE_LOG" "resume"
not_contains "$CODEX_FAKE_LOG" "workspace-write"
contains "$tmp/codex.stdin" "Read-only verdict round"

base_head="$(git -C "$tmp/repo" rev-parse HEAD)"
CODEX_FAKE_GIT_MUTATE=1 "$root/scripts/codex-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/codex.out" 1
[ "$(git -C "$tmp/repo" rev-parse HEAD)" = "$base_head" ] || fail "Codex peer changed HEAD"
if git -C "$tmp/repo" show-ref --verify -q refs/heads/peer-evil; then fail "Codex peer created a branch ref"; fi

: > "$CODEX_FAKE_LOG"
CODEX_ADD_DIRS="$tmp/scratch
$tmp/scratch2" "$root/scripts/codex-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/codex.out" 1
contains "$CODEX_FAKE_LOG" "--add-dir $tmp/scratch"
contains "$CODEX_FAKE_LOG" "--add-dir $tmp/scratch2"
if CODEX_ADD_DIRS="$tmp/does-not-exist" "$root/scripts/codex-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/codex.out" 1 >/dev/null 2>&1; then fail "missing CODEX_ADD_DIRS path was accepted"; fi

if CODEX_FAKE_AUTH=none "$root/scripts/codex-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/codex.out" 1 >/dev/null 2>&1; then fail "unauthenticated Codex was accepted"; fi
if CODEX_FAKE_RC=42 "$root/scripts/codex-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/codex.out" 1 >/dev/null 2>&1; then fail "failed Codex round was accepted"; fi
if CODEX_FAKE_EMPTY=1 "$root/scripts/codex-round.sh" "$tmp/repo" "$tmp/prompt" "$tmp/codex-empty.out" 1 >/dev/null 2>&1; then fail "empty Codex report was accepted"; fi
if PATH=/usr/bin:/bin "$root/scripts/peer-auth.sh" codex >/dev/null 2>&1; then fail "missing Codex CLI was accepted"; fi

printf 'PASS: round drivers\n'
