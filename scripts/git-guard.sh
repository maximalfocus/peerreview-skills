#!/usr/bin/env bash
# Install the PEER git-mutation guard and print the guard-dir path.
# Usage: guard_dir="$(bash git-guard.sh <protected_repo>)"; trap 'rm -rf "$guard_dir"' EXIT
# Then run the peer CLI with the guard first on PATH and these env vars set:
#   PATH="$guard_dir:$PATH" PEERREVIEW_REAL_GIT="$(command -v git)" \
#   PEERREVIEW_PROTECTED_REPO="$(cd <repo> && pwd -P)" <peer-cli> ...
# Inside the protected checkout the wrapper permits only an explicitly declared
# read-only set and denies everything else, so a subcommand nobody enumerated
# fails closed instead of being forwarded. Outside it, nothing is restricted:
# fixture repos elsewhere stay fully writable.
#
# Scope: this mediates git invoked as `git` through this PATH shim. It is defence
# in depth against an ERRANT co-editor, not a sandbox against a determined one,
# which can call the binary by absolute path; the peer CLI's own sandbox and the
# HOST's gate re-run remain the controls for that case. Do not describe this as
# complete Git mediation.
set -euo pipefail

protected_repo="${1:?protected_repo}"
# Resolve to a PHYSICAL path. The wrapper compares `pwd -P`-resolved targets
# against this value, so a logical path — macOS $TMPDIR is /var/folders/... with
# /var symlinked to /private/var — would match nothing and the guard would
# silently protect NOTHING while still appearing installed. Fail loudly instead.
protected_repo="$(cd "$protected_repo" 2>/dev/null && pwd -P)" || {
  printf 'peerreview: git-guard: protected repo path does not exist: %s\n' "$1" >&2
  exit 66
}
guard_dir="$(mktemp -d "${TMPDIR:-/tmp}/peerreview-git-guard.XXXXXX")"
real_git="$(command -v git)"
cat > "$guard_dir/git" <<'GUARD'
#!/usr/bin/env bash
set -euo pipefail
real_git="${PEERREVIEW_REAL_GIT:?}"
protected_repo="${PEERREVIEW_PROTECTED_REPO:?}"
args=("$@")
cmd=""
cmd_index=-1
git_cwd="$PWD"
explicit_git_dir=""
explicit_work_tree=""
separate_git_dir=""
config_file=""
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
    --git-dir=*) explicit_git_dir="${arg#*=}"; i=$((i + 1)); continue ;;
    --work-tree)
      explicit_work_tree="${args[$((i + 1))]:-}"
      i=$((i + 2)); continue ;;
    --work-tree=*) explicit_work_tree="${arg#*=}"; i=$((i + 1)); continue ;;
    --namespace|--config-env|-c) i=$((i + 2)); continue ;;
    --namespace=*|--config-env=*|-c=*) i=$((i + 1)); continue ;;
    --*) i=$((i + 1)); continue ;;
    -*) i=$((i + 1)); continue ;;
    *) cmd="$arg"; cmd_index="$i"; break ;;
  esac
done
# `--separate-git-dir` is a command option (init and clone), not a global one.
if [ "$cmd" = "init" ] || [ "$cmd" = "clone" ]; then
  i=$((cmd_index + 1))
  while [ "$i" -lt "${#args[@]}" ]; do
    arg="${args[$i]}"
    case "$arg" in
      --separate-git-dir) separate_git_dir="${args[$((i + 1))]:-}"; i=$((i + 2)); continue ;;
      --separate-git-dir=*) separate_git_dir="${arg#*=}" ;;
    esac
    i=$((i + 1))
  done
fi
# `git config --file/-f` selects the config file the command writes.
if [ "$cmd" = "config" ]; then
  i=$((cmd_index + 1))
  while [ "$i" -lt "${#args[@]}" ]; do
    arg="${args[$i]}"
    case "$arg" in
      --file|-f)
        if [ -n "${args[$((i + 1))]:-}" ]; then config_file="${args[$((i + 1))]}"; fi
        i=$((i + 2)); continue ;;
      --file=*) config_file="${arg#--file=}"; i=$((i + 1)); continue ;;
      -f*) config_file="${arg#-f}"; i=$((i + 1)); continue ;;
    esac
    i=$((i + 1))
  done
fi
resolved_cwd="$(cd "$git_cwd" 2>/dev/null && pwd -P || printf '%s' "$git_cwd")"
# Normalize existing paths and non-existing children through their physical
# parent so relative, `..`, and symlink aliases match the protected checkout.
resolve_path() {
  case "$1" in /*) target="$1" ;; *) target="$resolved_cwd/$1" ;; esac
  if [ -d "$target" ]; then
    cd "$target" 2>/dev/null && pwd -P || printf '%s' "$target"
  else
    parent="$(dirname "$target")"
    base="$(basename "$target")"
    physical_parent="$(cd "$parent" 2>/dev/null && pwd -P || printf '%s' "$parent")"
    printf '%s/%s' "$physical_parent" "$base"
  fi
}
protect_git_dir() {
  target="$(resolve_path "$1")"
  case "$target" in "$protected_repo/.git"|"$protected_repo/.git"/*) protected=1 ;; esac
}
protect_work_tree() {
  target="$(resolve_path "$1")"
  case "$target" in "$protected_repo"|"$protected_repo"/*) protected=1 ;; esac
}
protected=0
case "$resolved_cwd" in "$protected_repo"|"$protected_repo"/*) protected=1 ;; esac
[ -n "$explicit_git_dir" ] && protect_git_dir "$explicit_git_dir"
[ -n "$explicit_work_tree" ] && protect_work_tree "$explicit_work_tree"
[ -n "$separate_git_dir" ] && protect_git_dir "$separate_git_dir"
[ -n "$config_file" ] && protect_git_dir "$config_file"
[ -n "${GIT_DIR:-}" ] && protect_git_dir "$GIT_DIR"
[ -n "${GIT_WORK_TREE:-}" ] && protect_work_tree "$GIT_WORK_TREE"
[ -n "${GIT_COMMON_DIR:-}" ] && protect_git_dir "$GIT_COMMON_DIR"
[ -n "${GIT_OBJECT_DIRECTORY:-}" ] && protect_git_dir "$GIT_OBJECT_DIRECTORY"
[ -n "${GIT_INDEX_FILE:-}" ] && protect_git_dir "$GIT_INDEX_FILE"
[ -n "${GIT_CONFIG_GLOBAL:-${GIT_CONFIG:-}}" ] && protect_git_dir "${GIT_CONFIG_GLOBAL:-$GIT_CONFIG}"
[ -n "${GIT_CONFIG_SYSTEM:-}" ] && protect_git_dir "$GIT_CONFIG_SYSTEM"
# Deny by default inside the protected checkout. An enumerated DENYlist forwarded
# every subcommand nobody thought of — including plumbing. That mattered because
# `git update-index --assume-unchanged <path>` removes a real on-disk modification
# from BOTH `git status` and `git diff HEAD`, the two commands the HOST re-verifies
# each round with, so an errant co-editor's edit could pass that audit unseen.
if [ "$protected" -eq 1 ]; then
  allowed=0
  case "$cmd" in
    # No subcommand at all (`git --version`, `git --help`, `git --exec-path`):
    # these inspect the installation, never the repository.
    "") allowed=1 ;;
    blame|cat-file|check-ignore|describe) allowed=1 ;;
    diff|diff-files|diff-index|diff-tree) allowed=1 ;;
    for-each-ref|grep|help|log) allowed=1 ;;
    ls-files|ls-tree|merge-base|name-rev) allowed=1 ;;
    rev-list|rev-parse|shortlog|show|show-ref) allowed=1 ;;
    status|var|version|whatchanged) allowed=1 ;;
    config)
      # `git config` both reads and writes; permit only its read forms, so
      # `--get x` passes while `x value` (and every --file/--global write
      # redirected at the protected repo) is denied.
      for arg in "$@"; do
        case "$arg" in
          --get|--get-all|--get-regexp|--get-urlmatch|--list|-l) allowed=1 ;;
        esac
      done
      ;;
  esac
  if [ "$allowed" -ne 1 ]; then
    printf 'peerreview: PEER git mutation denied in reviewed repo: git %s\n' "${cmd:-<no subcommand>}" >&2
    exit 77
  fi
fi
exec "$real_git" "$@"
GUARD
chmod +x "$guard_dir/git"
printf '%s\n' "$guard_dir"
