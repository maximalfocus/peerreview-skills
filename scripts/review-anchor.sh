#!/usr/bin/env bash
# Durable convergence checkpoints without adding files to the reviewed tree.
# Usage: review-anchor.sh latest <repo> [--fetch]
#        review-anchor.sh create <repo> <full|incremental> --verdict <verdict-out>
# create anchors only the head a CONVERGED verdict judged: <verdict-out> is the round driver's
# --verdict output in the review's charter folder (charter-temp.sh new <repo>, bound to this
# checkout), its first line CONVERGED, and its <verdict-out>.head stamp names HEAD and the tree.
# (2026-10-15: anchors were cut twice on NOT CONVERGED heads, and a worker took another review's
# folder by recency.)
set -euo pipefail

cmd=${1:-}; repo=${2:-}
[[ -n $cmd && -n $repo ]] || { sed -n '2,9p' "$0" >&2; exit 64; }
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

refuse() { echo "refusing to anchor: $*" >&2; exit 65; }

# verdict_gate <verdict-out>: the checks above, every one fail-closed.
verdict_gate() {
  local file=$1 dir real bound top first stamp want
  [[ -n $file && -f $file && ! -L $file ]] || refuse "no verdict file (pass --verdict <verdict-out>): ${file:-none}"
  dir=$(cd -- "$(dirname -- "$file")" 2>/dev/null && pwd -P) || refuse "verdict folder unreadable: $file"
  [[ ${dir##*/} == peerreview-charter.?* && -f $dir/.peerreview-owned && ! -L $dir/.peerreview-owned ]] ||
    refuse "the verdict is not in a charter folder made by charter-temp.sh new: $file"
  [[ -f $dir/.peerreview-repo && ! -L $dir/.peerreview-repo ]] ||
    refuse "the charter folder is bound to no repository (make it with charter-temp.sh new <repo>): $dir"
  bound=$(cat -- "$dir/.peerreview-repo")
  top=$(git -C "$repo" rev-parse --show-toplevel) && top=$(cd -- "$top" && pwd -P) || refuse "no top level: $repo"
  [[ $bound == "$top" ]] || refuse "the charter folder belongs to $bound, not $top"
  IFS= read -r first < "$file" || [[ -n $first ]] || refuse "the verdict is empty: $file"
  first=${first%$'\r'}
  [[ $first == CONVERGED || $first == "CONVERGED "* ]] || refuse "the verdict's first line is not CONVERGED: $first"
  stamp=$file.head
  [[ -f $stamp && ! -L $stamp ]] || refuse "no head stamp beside the verdict (run the verdict with a round driver): $stamp"
  [[ ! $file -nt $stamp ]] || refuse "the verdict changed after its round stamped it: $file"
  want=$(cd -- "$repo" && . "$script_dir/round-support.sh" &&
    printf 'head %s\nfingerprint %s' "$(git rev-parse HEAD)" "$(rd_tree_fingerprint)") || refuse "cannot read HEAD of $repo"
  [[ $(cat -- "$stamp") == "$want" ]] || refuse "the verdict judged another head or tree than HEAD $(git -C "$repo" rev-parse --short=12 HEAD)"
}
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 69; }

latest() {
  git -C "$repo" for-each-ref --sort=-refname \
    --format='%(refname:short)%09%(*objectname)' 'refs/tags/peerreview/converged/*' |
    # Read the whole list and keep its first annotated row: an `exit` here closes the pipe early
    # and `git for-each-ref` gets SIGPIPE (status 141 under pipefail) once the tag list outgrows
    # the pipe buffer.
    awk -F '\t' 'NF == 2 && $2 != "" && !found { print $1 "\t" $2; found = 1 }'
}

case "$cmd" in
  latest)
    if [[ ${3:-} == --fetch ]] && git -C "$repo" remote get-url origin >/dev/null 2>&1; then
      git -C "$repo" fetch --tags origin
    fi
    row=$(latest); [[ -n $row ]] && printf '%s\n' "$row" || printf 'NONE\n'
    ;;
  create)
    mode=${3:-}; [[ $mode == full || $mode == incremental ]] || { echo "mode must be full or incremental" >&2; exit 64; }
    [[ -z $(git -C "$repo" status --porcelain) ]] || { echo "reviewed tree must be clean before anchoring" >&2; exit 1; }
    [[ ${4:-} == --verdict && $# -eq 5 ]] || refuse "usage: create <repo> <full|incremental> --verdict <verdict-out>"
    verdict_gate "$5"
    tree=$(git -C "$repo" rev-parse HEAD); row=$(latest)
    if [[ -n $row ]]; then base_tag=${row%%$'\t'*}; base_commit=${row#*$'\t'}; serial=$((10#$(basename "$base_tag" | cut -d- -f1) + 1))
    else base_tag=none; base_commit=none; serial=1; fi
    printf -v serial_padded '%06d' "$serial"
    tag="peerreview/converged/${serial_padded}-$(date -u +%Y%m%dT%H%M%SZ)-$(git -C "$repo" rev-parse --short=12 HEAD)"
    git -C "$repo" show-ref --verify --quiet "refs/tags/$tag" && { echo "anchor collision: $tag" >&2; exit 1; }
    message=$(printf 'Peerreview-Anchor: 1\nMode: %s\nBase-Anchor: %s\nBase-Commit: %s\nTree: %s' "$mode" "$base_tag" "$base_commit" "$tree")
    git -C "$repo" tag -a "$tag" "$tree" -m "$message"
    printf '%s\n' "$tag"
    ;;
  *) echo "unknown command: $cmd" >&2; exit 64 ;;
esac
