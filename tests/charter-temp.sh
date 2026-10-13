#!/usr/bin/env bash
# charter-temp.sh: `clean` removes the review's own folder with what the review put in it,
# and nothing else.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/charter-temp.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp/t"; mkdir -p "$TMPDIR"
fails=0
check() { # name, got, want
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1 (got '$2', want '$3')"; fails=$((fails + 1))
  fi
}
run() { bash "$script" "$@" >/dev/null 2>"$tmp/err"; echo $?; }
state() { [ -e "$1" ] && echo there || echo gone; }

# an empty review folder
p="$(bash "$script" new)"; d="${p%/*}"
check "new: a PROBLEM.md in a peerreview-charter folder" "${p##*/} ${d##*/}" \
  "PROBLEM.md ${d##*/}"
check "new: the folder is private" "$(stat -f %Lp "$d" 2>/dev/null || stat -c %a "$d")" "700"
check "clean of an empty review folder: exit 0" "$(run clean "$p")" "0"
check "clean of an empty review folder: gone" "$(state "$d")" "gone"

# a folder the review filled: round files, a gate file, an evidence subfolder,
# and links that point outside
p="$(bash "$script" new)"; d="${p%/*}"
echo keep > "$tmp/outside.txt"; mkdir "$tmp/outside-dir"; echo keep > "$tmp/outside-dir/file"
echo x > "$d/r1.prompt"; echo x > "$d/r1.out"; echo x > "$d/gate.txt"
mkdir -p "$d/evidence/sub"; echo x > "$d/evidence/sub/read.txt"
ln -s "$tmp/outside.txt" "$d/link-to-file"; ln -s "$tmp/outside-dir" "$d/link-to-dir"
check "clean of a filled review folder: exit 0" "$(run clean "$p")" "0"
check "clean of a filled review folder: gone" "$(state "$d")" "gone"
check "a file a link inside pointed to is untouched" \
  "$(cat "$tmp/outside.txt" 2>/dev/null)" "keep"
check "a folder a link inside pointed to is untouched" \
  "$(cat "$tmp/outside-dir/file" 2>/dev/null)" "keep"
check "clean a second time: refused (exit 2)" "$(run clean "$p")" "2"
check "the refusal names the path" "$(cat "$tmp/err")" \
  "refusing to clean non-peerreview charter path: $p"

# refusals: each leaves its folder as it was
refused() { # name, path given to clean, a path that must still exist
  check "$1: refused (exit 2)" "$(run clean "$2")" "2"
  check "$1: nothing removed" "$(state "$3")" "there"
}
make() { # folder name under the temp root, with a PROBLEM.md; prints the folder
  mkdir -p "$tmp/t/$1"; : > "$tmp/t/$1/PROBLEM.md"; echo "$tmp/t/$1"
}
p="$(bash "$script" new)"; d="${p%/*}"; echo x > "$d/r1.prompt"
refused "another file name in the folder" "$d/r1.prompt" "$d/r1.prompt"
refused "the folder itself" "$d" "$d/PROBLEM.md"
refused "no path" "" "$d/PROBLEM.md"
refused "a bare PROBLEM.md" "PROBLEM.md" "$d/PROBLEM.md"
f="$(make not-a-charter)"; : > "$f/.peerreview-owned"
refused "a folder of another name, with a marker" "$f/PROBLEM.md" "$f/PROBLEM.md"
f="$(make peerreview-charter.)"; : > "$f/.peerreview-owned"
refused "a folder named with nothing after the dot" "$f/PROBLEM.md" "$f/PROBLEM.md"
f="$(make peerreview-charter.nomark)"
refused "a folder of the right name without the marker" "$f/PROBLEM.md" "$f/PROBLEM.md"
f="$(make peerreview-charter.linkmark)"; ln -s "$d/.peerreview-owned" "$f/.peerreview-owned"
refused "a marker that is a link" "$f/PROBLEM.md" "$f/PROBLEM.md"
f="$(make peerreview-charter.dirmark)"; mkdir "$f/.peerreview-owned"
refused "a marker that is a folder" "$f/PROBLEM.md" "$f/PROBLEM.md"
ln -s "$d" "$tmp/t/peerreview-charter.link"
refused "a link to a real review folder" "$tmp/t/peerreview-charter.link/PROBLEM.md" \
  "$d/PROBLEM.md"
f="$(make elsewhere)"; : > "$f/.peerreview-owned"
ln -s "$f" "$tmp/t/peerreview-charter.away"
refused "a link of the right name to another folder" \
  "$tmp/t/peerreview-charter.away/PROBLEM.md" "$f/PROBLEM.md"
check "after every refusal the real review folder still holds its files" \
  "$(ls -A "$d" | sort | tr '\n' ' ')" ".peerreview-owned PROBLEM.md r1.prompt "
check "the real one still cleans: exit 0" "$(run clean "$p")" "0"

# a folder whose PROBLEM.md was removed by hand still cleans (the path names the folder)
p="$(bash "$script" new)"; d="${p%/*}"; rm -f "$p"; echo x > "$d/r1.out"
check "a review folder without its PROBLEM.md: exit 0 and gone" \
  "$(run clean "$p") $(state "$d")" "0 gone"

check "usage on another word: exit 2" "$(run sweep)" "2"
if [ "$fails" -eq 0 ]; then
  echo "charter-temp: all pass"
else
  echo "charter-temp: $fails FAILED"; exit 1
fi
