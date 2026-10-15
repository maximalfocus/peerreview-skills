#!/usr/bin/env bash
# review-anchor.sh: `latest` and `create` must succeed whatever the number of anchor tags. The reader of the tag list
# stopped after the first row, so `git for-each-ref` got SIGPIPE once its output outgrew the pipe buffer and, under
# `set -o pipefail`, the script exited 141 (peerreview-skills#38).
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
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
repo="$tmp/repo"; git init -q "$repo"
git -C "$repo" commit -q --allow-empty -m base
# 3000 anchor refs (about 330 KB of `for-each-ref` output, far over any pipe buffer) pointing
# at one annotated tag object
git -C "$repo" tag -a -m seed seed-tag HEAD
obj=$(git -C "$repo" rev-parse seed-tag); git -C "$repo" tag -d seed-tag >/dev/null
n=3000
for i in $(seq 1 "$n"); do
  printf 'create refs/tags/peerreview/converged/%06d-20260101T000000Z-aaaaaaaaaaaa %s\n' "$i" "$obj"
done | git -C "$repo" update-ref --stdin
git -C "$repo" commit -q --allow-empty -m next

out=$(bash "$script" latest "$repo" 2>"$tmp/err"); code=$?
check "latest exits 0 with $n anchors" "$code" 0
newest="peerreview/converged/$(printf '%06d' "$n")-20260101T000000Z-aaaaaaaaaaaa"
check "latest names the newest serial" "${out%%$'\t'*}" "$newest"

out=$(bash "$script" create "$repo" full 2>"$tmp/err"); code=$?
check "create exits 0 with $n anchors" "$code" 0
next="peerreview/converged/$(printf '%06d' $((n + 1)))-"
case "$out" in
  "$next"*) check "create takes the next serial" ok ok ;;
  *) check "create takes the next serial" "$out" "${next}…" ;;
esac
check "the tag exists and is annotated" "$(git -C "$repo" cat-file -t "$out" 2>/dev/null)" tag

# a repository with no anchor, and a lightweight tag among them (skipped: no object behind it)
repo2="$tmp/repo2"; git init -q "$repo2"; git -C "$repo2" commit -q --allow-empty -m base
git -C "$repo2" tag peerreview/converged/000009-20260101T000000Z-bbbbbbbbbbbb
check "latest with only a lightweight tag" "$(bash "$script" latest "$repo2" 2>/dev/null)" NONE
out=$(bash "$script" create "$repo2" incremental 2>"$tmp/err"); code=$?
check "create with no anchor exits 0" "$code" 0
case "$out" in
  peerreview/converged/000001-*) check "first serial is 1" ok ok ;;
  *) check "first serial is 1" "$out" "…/000001-…" ;;
esac
# the exit code of a real failure is still the failure's: a dirty tree
echo x > "$repo2/dirty"
bash "$script" create "$repo2" full >/dev/null 2>"$tmp/err"
check "dirty tree still refuses (exit 1)" "$?" 1

[ "$fails" -eq 0 ] && echo "PASS" || { echo "FAILED: $fails"; exit 1; }
