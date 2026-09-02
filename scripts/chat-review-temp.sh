#!/usr/bin/env bash
set -euo pipefail

root=${TMPDIR:-/tmp}
root=${root%/}

case "${1:-}" in
  new)
    old_umask=$(umask)
    umask 077
    dir=$(mktemp -d "$root/peerreview-chat.XXXXXX")
    : > "$dir/.peerreview-chat-owned"
    git -C "$dir" init -q
    git -C "$dir" config user.name "Peerreview Chat Host"
    git -C "$dir" config user.email "peerreview-chat@localhost"
    umask "$old_umask"
    printf '%s\n' "$dir"
    ;;
  clean)
    dir=${2:-}
    resolved=$(cd "${dir:-/nonexistent}" 2>/dev/null && pwd -P) || {
      echo "refusing to clean missing chat-review workspace: $dir" >&2
      exit 2
    }
    # Compare like with like: `pwd -P` resolves symlinks, and on macOS $TMPDIR
    # is /var/... while its physical path is /private/var/..., so an unresolved
    # $root never matches and the guard refuses every workspace `new` created.
    root_p=$(cd "$root" 2>/dev/null && pwd -P) || root_p=$root
    case "$resolved" in
      "$root_p"/peerreview-chat.*|"$root"/peerreview-chat.*) ;;
      *) echo "refusing to clean non-peerreview chat path: $resolved" >&2; exit 2 ;;
    esac
    if [[ ! -f "$resolved/.peerreview-chat-owned" || -L "$resolved/.peerreview-chat-owned" ]]; then
      echo "refusing to clean unowned chat-review workspace: $resolved" >&2
      exit 2
    fi
    rm -rf -- "$resolved"
    ;;
  *)
    echo "usage: $0 new | clean <temp-workspace>" >&2
    exit 2
    ;;
esac
