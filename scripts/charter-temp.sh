#!/usr/bin/env bash
set -euo pipefail

# The review's private folder. `new` makes it and prints the path of its PROBLEM.md; the HOST
# keeps the review's own files there too (round prompts, outputs, gate files, a PEER evidence
# subfolder). `clean` removes that folder with everything in it, and nothing else: it refuses
# unless the path is the PROBLEM.md of a folder `new` made (its name, its owner marker), that
# folder is a real directory and not a link, and it and the marker belong to the caller. It
# removes by the folder's resolved path and never follows a link inside it.

root=${TMPDIR:-/tmp}
root=${root%/}

refuse() {
  echo "refusing to clean non-peerreview charter path: $1" >&2
  exit 2
}

owner_of() {
  case $1 in -*) set -- "./$1" ;; esac
  case $(uname -s) in
    Darwin) stat -f %u "$1" 2>/dev/null ;;
    *) stat -c %u "$1" 2>/dev/null ;;
  esac
}

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
    marker="$dir/.peerreview-owned"
    [[ ${path##*/} == PROBLEM.md && ${dir##*/} == peerreview-charter.?* ]] || refuse "$path"
    [[ -d $dir && ! -L $dir && -f $marker && ! -L $marker ]] || refuse "$path"
    me=$(id -u)
    [[ $(owner_of "$dir") == "$me" && $(owner_of "$marker") == "$me" ]] || refuse "$path"
    real=$(cd -- "$dir" 2>/dev/null && pwd -P) || refuse "$path"
    root_path=${root:-/}
    root_real=$(cd -- "$root_path" 2>/dev/null && pwd -P) || refuse "$path"
    parent=${real%/*}
    [[ -n $parent ]] || parent=/
    [[ $parent == "$root_real" ]] || refuse "$path"
    [[ ${real##*/} == "${dir##*/}" ]] || refuse "$path"
    rm -rf -- "$real"
    [[ ! -e $real ]] || { echo "the charter folder could not be removed: $path" >&2; exit 1; }
    ;;
  *)
    echo "usage: $0 new | clean <temp-PROBLEM.md>" >&2
    exit 2
    ;;
esac
