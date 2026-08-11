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
    case "$resolved" in
      "$root"/peerreview-chat.*) ;;
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
