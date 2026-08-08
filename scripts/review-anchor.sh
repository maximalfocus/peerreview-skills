#!/usr/bin/env bash
# Durable convergence checkpoints without adding files to the reviewed tree.
# Usage: review-anchor.sh latest <repo> [--fetch]
#        review-anchor.sh create <repo> <full|incremental>
set -euo pipefail

cmd=${1:-}; repo=${2:-}
[[ -n $cmd && -n $repo ]] || { sed -n '2,4p' "$0" >&2; exit 64; }
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo: $repo" >&2; exit 69; }

latest() {
  git -C "$repo" for-each-ref --sort=-refname \
    --format='%(refname:short)%09%(*objectname)' 'refs/tags/peerreview/converged/*' |
    awk -F '\t' 'NF == 2 && $2 != "" { print $1 "\t" $2; exit }'
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
