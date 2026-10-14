#!/usr/bin/env bash
# review-anchor.sh: `latest` and `create` answer on a repository with many anchors. A pipeline that
# ends in an early-exiting reader dies with SIGPIPE (141) under `set -o pipefail` once the
# producer's output is larger than the pipe buffer, so the anchor count here is well past it.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${REVIEW_ANCHOR_SCRIPT:-$root/scripts/review-anchor.sh}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0
check() { # name, got, want
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1 (got '$2', want '$3')"; fails=$((fails + 1))
  fi
}
repo="$tmp/repo"
git init -q "$repo"
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m base
head="$(git -C "$repo" rev-parse HEAD)"
n=1500
msg="Peerreview-Anchor: 1"
for i in $(seq 1 "$n"); do
  printf 'tag peerreview/converged/%06d-20261014T000000Z-%s\nfrom %s\n' "$i" "${head:0:12}" "$head"
  printf 'tagger t <t@example.invalid> 1760400000 +0000\ndata %d\n%s\n\n' "$((${#msg} + 1))" "$msg"
done > "$tmp/stream"
git -C "$repo" fast-import --quiet < "$tmp/stream" 2>"$tmp/fi-err"
count="$(git -C "$repo" tag --list 'peerreview/converged/*' | wc -l | tr -d ' ')"
check "the fixture holds $n anchors" "$count" "$n"
newest="$(printf 'peerreview/converged/%06d-20261014T000000Z-%s' "$n" "${head:0:12}")"
for k in 1 2 3 4 5; do
  out="$(bash "$script" latest "$repo" 2>"$tmp/err")"; rc=$?
  check "latest run $k exits 0" "$rc" "0"
  check "latest run $k names the newest anchor" "${out%%$'\t'*}" "$newest"
done
out="$(bash "$script" create "$repo" full 2>"$tmp/err")"; rc=$?
check "create exits 0" "$rc" "0"
want="peerreview/converged/$(printf '%06d' $((n + 1)))-"
check "create names the next serial" "${out:0:${#want}}" "$want"
echo
if [ "$fails" -eq 0 ]; then
  echo "review-anchor: all ok"
else
  echo "review-anchor: $fails FAILED"; exit 1
fi
