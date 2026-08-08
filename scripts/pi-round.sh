#!/usr/bin/env bash
# Drive one Pi/OpenAI-subscription co-edit or read-only verdict round.
# Usage: pi-round.sh <repo_dir> <prompt_file> <last_message_out> [round|--verdict]
set -euo pipefail

repo_dir="${1:?repo_dir}"
prompt_file="${2:?prompt_file}"
out="${3:?last_message_out}"
round="${4:-1}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/peer-auth.sh" pi >/dev/null
git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { printf 'peerreview: %s is not a git repo.\n' "$repo_dir" >&2; exit 69; }
[ -f "$prompt_file" ] || { printf 'peerreview: prompt file missing: %s\n' "$prompt_file" >&2; exit 66; }

cd "$repo_dir"

timeout_s="${PI_ROUND_TIMEOUT:-1800}"
TO_CMD=""
if [ "$timeout_s" != "0" ]; then
  if command -v timeout >/dev/null 2>&1; then TO_CMD="timeout $timeout_s"
  elif command -v gtimeout >/dev/null 2>&1; then TO_CMD="gtimeout $timeout_s"
  else printf 'peerreview: no timeout/gtimeout on PATH; running Pi unbounded.\n' >&2; fi
fi

# Keep peer sessions separate from the user's interactive Pi history. A fresh
# round creates the latest session in this repo-specific directory; later rounds
# and the verdict continue it.
repo_key="$(printf '%s' "$repo_dir" | cksum | awk '{print $1}')"
session_dir="${PEERREVIEW_PI_SESSION_DIR:-${TMPDIR:-/tmp}/peerreview-pi-sessions/$repo_key}"
mkdir -p "$session_dir"

args=(-p --provider openai-codex --session-dir "$session_dir" --no-extensions --no-skills --no-prompt-templates)
if [ "$round" = "--verdict" ]; then
  args+=(-c --tools read,grep,find,ls --append-system-prompt "Read-only verdict: do not edit files or run commands.")
else
  args+=(--tools read,write,edit,bash,grep,find,ls --append-system-prompt "You are the PEER co-editor. The HOST owns git: never commit, push, change branches/tags/remotes, or rewrite history.")
  if [ "$round" != "1" ] && [ "$round" != "--fresh" ]; then args+=(-c); fi
fi

# Pi intentionally has no permission popups or sandbox. Put a target-scoped git
# guard first on PATH: the PEER may create temporary fixture repos while running
# tests, but cannot mutate the reviewed repo or its remotes. The prompt repeats
# the boundary; HOST still audits HEAD/status.
guard_dir="$(mktemp -d "${TMPDIR:-/tmp}/peerreview-git-guard.XXXXXX")"
trap 'rm -rf "$guard_dir"' EXIT
real_git="$(command -v git)"
cat > "$guard_dir/git" <<'GUARD'
#!/usr/bin/env bash
set -euo pipefail
real_git="${PEERREVIEW_REAL_GIT:?}"
protected_repo="${PEERREVIEW_PROTECTED_REPO:?}"
args=("$@")
cmd=""
git_cwd="$PWD"
explicit_git_dir=""
i=0
while [ "$i" -lt "${#args[@]}" ]; do
  arg="${args[$i]}"
  case "$arg" in
    -C)
      path="${args[$((i + 1))]:-}"
      case "$path" in /*) git_cwd="$path" ;; *) git_cwd="$git_cwd/$path" ;; esac
      i=$((i + 2)); continue ;;
    --git-dir)
      explicit_git_dir="${args[$((i + 1))]:-}"
      i=$((i + 2)); continue ;;
    --git-dir=*) explicit_git_dir="${arg#--git-dir=}"; i=$((i + 1)); continue ;;
    --work-tree|--namespace|--config-env|-c) i=$((i + 2)); continue ;;
    --work-tree=*|--namespace=*|--config-env=*|-c=*) i=$((i + 1)); continue ;;
    --*) i=$((i + 1)); continue ;;
    -*) i=$((i + 1)); continue ;;
    *) cmd="$arg"; break ;;
  esac
done
resolved_cwd="$(cd "$git_cwd" 2>/dev/null && pwd -P || printf '%s' "$git_cwd")"
protected=0
case "$resolved_cwd" in "$protected_repo"|"$protected_repo"/*) protected=1 ;; esac
if [ -n "$explicit_git_dir" ]; then
  case "$explicit_git_dir" in /*) resolved_git_dir="$explicit_git_dir" ;; *) resolved_git_dir="$resolved_cwd/$explicit_git_dir" ;; esac
  case "$resolved_git_dir" in "$protected_repo/.git"|"$protected_repo/.git"/*) protected=1 ;; esac
fi
case "$cmd" in
  add|am|apply|bisect|branch|checkout|cherry-pick|clean|clone|commit|config|fast-import|fetch|filter-branch|gc|init|merge|mv|notes|pull|push|rebase|remote|replace|reset|restore|revert|rm|stash|submodule|switch|symbolic-ref|tag|update-ref|worktree)
    if [ "$protected" -eq 1 ]; then
      printf 'peerreview: PEER git mutation denied in reviewed repo: git %s\n' "$cmd" >&2
      exit 77
    fi
    ;;
esac
exec "$real_git" "$@"
GUARD
chmod +x "$guard_dir/git"

rc=0
# shellcheck disable=SC2086
PATH="$guard_dir:$PATH" PEERREVIEW_REAL_GIT="$real_git" PEERREVIEW_PROTECTED_REPO="$(pwd -P)" $TO_CMD pi "${args[@]}" < "$prompt_file" > "$out" || rc=$?
if [ "$rc" -eq 124 ]; then
  printf 'peerreview: Pi round timed out after %ss (override: PI_ROUND_TIMEOUT, 0=disable).\n' "$timeout_s" >&2
fi
[ "$rc" -eq 0 ] || exit "$rc"
[ -s "$out" ] || { printf 'peerreview: Pi returned no report.\n' >&2; exit 70; }
