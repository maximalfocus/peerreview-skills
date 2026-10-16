#!/usr/bin/env bash
# review-anchor.sh: `latest` and `create` must succeed whatever the number of anchor tags. The
# reader of the tag list stopped after the first row, so `git for-each-ref` got SIGPIPE once its
# output outgrew the pipe buffer and, under `set -o pipefail`, the script exited 141
# (peerreview-skills#38). `create` anchors only a head a CONVERGED verdict judged, from the
# charter folder bound to that checkout (2026-10-15: anchors cut on NOT CONVERGED heads twice; a
# worker took another review's folder by recency).
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
export TMPDIR="$tmp"

# verdict <repo> <first line> [unbound]: a charter folder made by charter-temp.sh new (bound to
# <repo> unless "unbound"), a verdict file in it, and the stamp a round driver writes for the
# head it judged; prints the verdict path.
verdict() {
  local p dir
  if [ "${3:-}" = unbound ]; then p=$(bash "$root/scripts/charter-temp.sh" new)
  else p=$(bash "$root/scripts/charter-temp.sh" new "$1"); fi
  dir=${p%/*}
  printf '%s\nreasons\n' "$2" > "$dir/verdict.md"
  (cd "$1" && . "$root/scripts/round-support.sh" && rd_verdict_stamp "$dir/verdict.md" "$(rd_tree_fingerprint)")
  printf '%s\n' "$dir/verdict.md"
}
CONV="CONVERGED — no substantive defects remain"

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

out=$(bash "$script" create "$repo" full --verdict "$(verdict "$repo" "$CONV")" 2>"$tmp/err"); code=$?
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
out=$(bash "$script" create "$repo2" incremental --verdict "$(verdict "$repo2" "$CONV")" 2>"$tmp/err"); code=$?
check "create with no anchor exits 0" "$code" 0
case "$out" in
  peerreview/converged/000001-*) check "first serial is 1" ok ok ;;
  *) check "first serial is 1" "$out" "…/000001-…" ;;
esac
# the exit code of a real failure is still the failure's: a dirty tree
echo x > "$repo2/dirty"
bash "$script" create "$repo2" full --verdict "$(verdict "$repo2" "$CONV")" >/dev/null 2>"$tmp/err"
check "dirty tree still refuses (exit 1)" "$?" 1
rm -f "$repo2/dirty"

# --- the verdict gate: each refusal exits 65, names its reason and creates no tag ---------------
r="$tmp/r3"; git init -q "$r"; git -C "$r" commit -q --allow-empty -m base
other="$tmp/r4"; git init -q "$other"; git -C "$other" commit -q --allow-empty -m base
tags() { git -C "$r" tag -l 'peerreview/converged/*' | wc -l | tr -d ' '; }
refused() { # name, expected stderr fragment, create args after the mode...
  local name=$1 want=$2; shift 2
  bash "$script" create "$r" full "$@" >/dev/null 2>"$tmp/err"; local code=$?
  check "$name: exit 65" "$code" 65
  grep -qF -- "$want" "$tmp/err" && check "$name: names why" ok ok ||
    check "$name: names why" "$(cat "$tmp/err")" "…${want}…"
  check "$name: no tag" "$(tags)" 0
}
refused "no --verdict" "usage: create"
refused "missing verdict file" "no verdict file" --verdict "$tmp/nowhere.md"
refused "NOT CONVERGED first line" "first line is not CONVERGED" --verdict "$(verdict "$r" "NOT CONVERGED — round 2 needed")"
refused "bold CONVERGED" "first line is not CONVERGED" --verdict "$(verdict "$r" "**CONVERGED** — no substantive defects remain")"
refused "CONVERGED later in the file" "first line is not CONVERGED" --verdict "$(verdict "$r" "Summary first
CONVERGED — no substantive defects remain")"
v=$(verdict "$r" "$CONV"); git -C "$r" commit -q --allow-empty -m "a later commit"
refused "verdict judged an earlier head" "judged another head" --verdict "$v"
v=$(verdict "$r" "$CONV"); rm -f "$v.head"
refused "no head stamp" "no head stamp" --verdict "$v"
v=$(verdict "$r" "$CONV"); sleep 1; printf '%s\n' "$CONV" > "$v"
refused "verdict rewritten after its stamp" "changed after its round stamped it" --verdict "$v"
# Equal mtimes occur naturally on coarse filesystems: content binding must catch this too.
v=$(verdict "$r" "NOT CONVERGED — round 2 needed")
printf '%s\n' "$CONV" > "$v"; touch -r "$v.head" "$v"
refused "rewritten verdict with equal mtime" "the verdict changed" --verdict "$v"
for input in verdict.md verdict.md.head .peerreview-repo; do
  v=$(verdict "$r" "$CONV"); target="${v%/*}/$input"
  chmod 000 "$target"
  bash "$script" create "$r" full --verdict "$v" >/dev/null 2>"$tmp/err"; code=$?
  check "unreadable $input refuses" "$code" 65
  check "unreadable $input creates no tag" "$(tags)" 0
  chmod 600 "$target"
done
refused "another checkout's charter folder" "the charter folder belongs to" --verdict "$(verdict "$other" "$CONV")"
refused "unbound charter folder" "bound to no repository" --verdict "$(verdict "$r" "$CONV" unbound)"
v=$(verdict "$r" "$CONV"); mkdir "$tmp/loose"; cp "$v" "$v.head" "$tmp/loose/"
refused "verdict outside a charter folder" "not in a charter folder" --verdict "$tmp/loose/verdict.md"
v=$(verdict "$r" "$CONV"); ln -s "$v" "$tmp/link.md"; ln -s "$v.head" "$tmp/link.md.head"
refused "verdict through a symlink" "no verdict file" --verdict "$tmp/link.md"

# the passing case: CONVERGED (also with a CR line end) for this head, from its own bound folder
v=$(verdict "$r" "$CONV"$'\r')
out=$(bash "$script" create "$r" full --verdict "$v" 2>"$tmp/err"); code=$?
check "CONVERGED for this head anchors" "$code" 0
check "the anchor tags HEAD" "$(git -C "$r" rev-parse "$out^{commit}" 2>/dev/null)" "$(git -C "$r" rev-parse HEAD)"
v=$(verdict "$r" "CONVERGED")
# A valid first line need not have a trailing newline (read returns 1 at EOF).
printf CONVERGED > "$v"
(cd "$r" && . "$root/scripts/round-support.sh" && rd_verdict_stamp "$v" "$(rd_tree_fingerprint)")
bash "$script" create "$r" incremental --verdict "$v" >/dev/null 2>&1
check "a bare CONVERGED line anchors" "$?" 0
# charter-temp.sh new refuses a path that is not a repository
bash "$root/scripts/charter-temp.sh" new "$tmp/loose" >/dev/null 2>&1
check "charter-temp new <non-repo> refuses (exit 2)" "$?" 2

[ "$fails" -eq 0 ] && echo "PASS" || { echo "FAILED: $fails"; exit 1; }
