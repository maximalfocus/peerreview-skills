#!/usr/bin/env bash
set -euo pipefail

root=${TMPDIR:-/tmp}
root=${root%/}

case "${1:-}" in
  new)
    old_umask=$(umask)
    umask 077
    dir=$(mktemp -d "$root/peerreview-charter.XXXXXX")
    path="$dir/PROBLEM.md"
    : > "$dir/.peerreview-owned"
    : > "$path"
    umask "$old_umask"
    printf '%s\n' "$path"
    ;;
  clean)
    path=${2:-}
    dir=${path%/*}
    if [[ ${path##*/} != PROBLEM.md || ${dir##*/} != peerreview-charter.* || ! -f "$dir/.peerreview-owned" ]]; then
      echo "refusing to clean non-peerreview charter path: $path" >&2
      exit 2
    fi
    rm -f -- "$path" "$dir/.peerreview-owned"
    rmdir -- "$dir"
    ;;
  *)
    echo "usage: $0 new | clean <temp-PROBLEM.md>" >&2
    exit 2
    ;;
esac
