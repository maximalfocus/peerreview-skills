#!/usr/bin/env bash
# charter-temp.sh: `clean` removes the review's own folder with what the review put in it,
# and nothing else.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${CHARTER_TEMP_SCRIPT:-$root/scripts/charter-temp.sh}"
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
run_foreign_owner() {
  OWNER_TARGET="$1" PATH="$tmp/fakebin:$PATH" bash "$script" clean "$2" \
    >/dev/null 2>"$tmp/err"
  echo $?
}
run_failing_rm() {
  PATH="$tmp/failbin:$PATH" bash "$script" clean "$1" >/dev/null 2>"$tmp/err"
  echo $?
}
run_capture_rm() {
  CAPTURED="$tmp/removed-path" PATH="$tmp/capbin:$PATH" \
    bash "$script" clean "$1" >/dev/null 2>"$tmp/err"
  echo $?
}
run_successful_noop_rm() {
  PATH="$tmp/noopbin:$PATH" bash "$script" clean "$1" >/dev/null 2>"$tmp/err"
  echo $?
}
run_cd_failure() {
  BLOCK_MARKER="$1/.peerreview-owned" BLOCK_DIR="$1" EXPECTED_UID="$(id -u)" \
    PATH="$tmp/cdbin:$PATH" bash "$script" clean "$1/PROBLEM.md" \
    >/dev/null 2>"$tmp/err"
  echo $?
}
state() { [ -e "$1" ] && echo there || echo gone; }

# an empty review folder
p="$(bash "$script" new)"; d="${p%/*}"
check "new: a PROBLEM.md in a peerreview-charter folder" "${p##*/} ${d##*/}" \
  "PROBLEM.md ${d##*/}"
check "new: PROBLEM.md is empty" "$(wc -c < "$p" | tr -d ' ')" "0"
check "new: owner marker is regular" \
  "$(test -f "$d/.peerreview-owned" && test ! -L "$d/.peerreview-owned" && \
    echo regular || echo other)" "regular"
if [ "$(uname -s)" = Darwin ]; then
  mode=$(stat -f %Lp "$d")
else
  mode=$(stat -c %a "$d")
fi
check "new: the folder is private" "$mode" "700"
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

# Simulate a different owner without changing files outside this private temp root.
mkdir "$tmp/fakebin"
cat > "$tmp/fakebin/stat" <<'EOF'
#!/usr/bin/env bash
if [[ ${3:-} == "$OWNER_TARGET" ]]; then echo 999; else command -p stat "$@"; fi
EOF
chmod +x "$tmp/fakebin/stat"

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
f="$(make peerreview-charter.foreign-dir)"; : > "$f/.peerreview-owned"
check "a folder owned by another user: refused (exit 2)" \
  "$(run_foreign_owner "$f" "$f/PROBLEM.md")" "2"
check "a foreign-owned folder remains" "$(state "$f/PROBLEM.md")" "there"
f="$(make peerreview-charter.foreign-marker)"; : > "$f/.peerreview-owned"
check "a marker owned by another user: refused (exit 2)" \
  "$(run_foreign_owner "$f/.peerreview-owned" "$f/PROBLEM.md")" "2"
check "a foreign-owned marker remains" "$(state "$f/PROBLEM.md")" "there"
ln -s "$d" "$tmp/t/peerreview-charter.link"
refused "a link to a real review folder" "$tmp/t/peerreview-charter.link/PROBLEM.md" \
  "$d/PROBLEM.md"
f="$(make elsewhere)"; : > "$f/.peerreview-owned"
ln -s "$f" "$tmp/t/peerreview-charter.away"
refused "a link of the right name to another folder" \
  "$tmp/t/peerreview-charter.away/PROBLEM.md" "$f/PROBLEM.md"
mkdir -p "$tmp/external/peerreview-charter.same"
: > "$tmp/external/peerreview-charter.same/PROBLEM.md"
: > "$tmp/external/peerreview-charter.same/.peerreview-owned"
ln -s "$tmp/external/peerreview-charter.same" "$tmp/t/peerreview-charter.same"
refused "same-name symlink to a folder" \
  "$tmp/t/peerreview-charter.same/PROBLEM.md" \
  "$tmp/external/peerreview-charter.same/PROBLEM.md"
refused "root PROBLEM.md" "/PROBLEM.md" "$d/PROBLEM.md"
mkdir -p "$tmp/outside/peerreview-charter.lookalike"
f="$tmp/outside/peerreview-charter.lookalike"
: > "$f/PROBLEM.md"; : > "$f/.peerreview-owned"
refused "a marked folder outside TMPDIR" "$f/PROBLEM.md" "$f/PROBLEM.md"
refused "trailing slash after PROBLEM.md" "$p/" "$d/PROBLEM.md"
mkdir "$tmp/cdbin"
cat > "$tmp/cdbin/stat" <<'EOF'
#!/usr/bin/env bash
if [[ ${3:-} == "$BLOCK_MARKER" ]]; then
  chmod 000 "$BLOCK_DIR"
  echo "$EXPECTED_UID"
else
  command -p stat "$@"
fi
EOF
chmod +x "$tmp/cdbin/stat"
f="$(bash "$script" new)"; f="${f%/*}"
check "cd failure: refused (exit 2)" "$(run_cd_failure "$f")" "2"
chmod 700 "$f"
check "cd failure: folder remains" "$(state "$f/PROBLEM.md")" "there"
p="$(bash "$script" new)"; d="${p%/*}"
relative="${p#"$tmp/t"/}"
check "relative path: exit 0" \
  "$(cd "$tmp/t" && bash "$script" clean "$relative" >/dev/null 2>&1; echo $?)" "0"
check "relative path: gone" "$(state "$d")" "gone"
p="$(bash "$script" new)"; d="${p%/*}"
with_parent="${tmp}/t/../t/${d##*/}/PROBLEM.md"
check "path containing ..: exit 0" "$(run clean "$with_parent")" "0"
check "path containing ..: gone" "$(state "$d")" "gone"
p="$(bash "$script" new)"; d="${p%/*}"
mkdir "$tmp/capbin"
cat > "$tmp/capbin/rm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$3" > "$CAPTURED"
exec /bin/rm "$@"
EOF
chmod +x "$tmp/capbin/rm"
ln -s "$tmp/t" "$tmp/root-link"
physical=$(cd "$d" && pwd -P)
check "parent symlink: exit 0" \
  "$(run_capture_rm "$tmp/root-link/${d##*/}/PROBLEM.md")" "0"
check "removal uses the physical path" "$(cat "$tmp/removed-path")" "$physical"
check "parent symlink target: gone" "$(state "$d")" "gone"
f="$(make $'peerreview-charter.line\nbreak')"; : > "$f/.peerreview-owned"
check "newline in folder name: exit 0" "$(run clean "$f/PROBLEM.md")" "0"
f="$(make 'peerreview-charter.[glob]*')"; : > "$f/.peerreview-owned"
check "glob characters in folder name: exit 0" "$(run clean "$f/PROBLEM.md")" "0"
mkdir "$tmp/t/-root"
p="$(TMPDIR="$tmp/t/-root" bash "$script" new)"; d="${p%/*}"
check "path beginning with dash: exit 0" \
  "$(cd "$tmp/t" && TMPDIR="$tmp/t/-root" bash "$script" clean \
    "-root/${d##*/}/PROBLEM.md" >/dev/null 2>&1; echo $?)" "0"
check "path beginning with dash: gone" "$(state "$d")" "gone"
mkdir "$tmp/failbin"
cat > "$tmp/failbin/rm" <<'EOF'
#!/usr/bin/env bash
echo "simulated removal failure" >&2
exit 1
EOF
chmod +x "$tmp/failbin/rm"
p="$(bash "$script" new)"; d="${p%/*}"; echo x > "$d/r1.prompt"
check "failed removal: exit 1" "$(run_failing_rm "$p")" "1"
check "failed removal: folder remains" "$(state "$d")" "there"
check "failed removal: reported" "$(cat "$tmp/err")" "simulated removal failure"
mkdir "$tmp/noopbin"
cat > "$tmp/noopbin/rm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/noopbin/rm"
p="$(bash "$script" new)"; d="${p%/*}"
check "silent failed removal: exit 1" "$(run_successful_noop_rm "$p")" "1"
check "silent failed removal: reported" \
  "$(cat "$tmp/err")" "the charter folder could not be removed: $p"
check "silent failed removal: folder remains" "$(state "$d")" "there"
p="$(bash "$script" new)"; d="${p%/*}"; echo x > "$d/r1.prompt"
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
