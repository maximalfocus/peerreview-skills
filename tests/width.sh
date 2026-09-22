#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/width.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
long="$(printf 'word%.0s ' $(seq 1 60))"   # 300 characters of prose
cat > "$tmp/a.md" <<MD
---
name: demo
description: "$long"
argument-hint: "[x]"
---

# Demo — a heading that is deliberately far longer than one hundred characters, so the script must leave it for a hand

Plain paragraph: $long

- list item: $long
  continued on a second line that also belongs to the item.
1. numbered — ${long}
   - nested bullet: ${long}
     \`\`\`sh
     echo "indented fence: $long"
     \`\`\`
   The item's trailing paragraph, indented like its text, stays with it.
Unindented text after the list starts a new paragraph.

> A quoted line that is deliberately much longer than one hundred characters so that a naive wrap would touch it here.
> A second quoted line.

A wrapped line must never begin with a marker: alpha beta gamma delta epsilon zeta eta theta iota + caller \`with:\` + \`concurrency.group\`, and later - a dash - then 2. two and # hash and | pipe words words words.

| col | $long |
|---|---|

\`\`\`sh
echo "$long"
\`\`\`
MD
cp "$tmp/a.md" "$tmp/orig.md"
if bash "$script" check "$tmp/a.md" >/dev/null; then echo "check must fail on long lines" >&2; exit 1; fi
if out="$(bash "$script" fix "$tmp/a.md")"; then echo "fix must exit 1 while hand-work remains" >&2; exit 1; fi
# prose and list items are wrapped, every word kept
awk 'NR>1 && /^---$/{fm=0; next} NR==1{fm=1; next} /^[[:space:]]*```/{code=!code; next} !fm && !code && !/^\|/ && !/^#/ && !/^>/ && length>100 {print "still long: " $0; bad=1} END{exit bad}' "$tmp/a.md"
# body words only (front matter is folded on purpose). Compare the words, not
# an md5 (macOS-only), and require some: a second front-matter strip once
# emptied both sides, so the check passed vacuously on every platform.
words() {
  awk '{
    sub(/\r$/, "")
    if (NR == 1 && $0 == "---") { front_matter = 1; next }
    if (front_matter) { if ($0 == "---") front_matter = 0; next }
    for (i = 1; i <= NF; i++) print $i
  }' "$1" | LC_ALL=C sort
}
same_words() { [ "$(words "$1")" = "$(words "$2")" ]; }
[ -n "$(words "$tmp/orig.md")" ] || { echo "word extraction found no words" >&2; exit 1; }
same_words "$tmp/orig.md" "$tmp/a.md" || { echo "rewrap changed the words" >&2; exit 1; }
# Prove whitespace portability and that drop, add, and alteration mutations are rejected.
printf '%b' '---\r\nname: demo\r\n---\r\nalpha\tbeta gamma\r\n' > "$tmp/words-source.md"
printf '%b' 'gamma alpha beta\n' > "$tmp/words-same.md"
same_words "$tmp/words-source.md" "$tmp/words-same.md" \
  || { echo "word extraction mishandled whitespace or optional front matter" >&2; exit 1; }
for mutation in 'alpha beta' 'alpha beta gamma delta' 'alpha beta changed'; do
  printf '%s\n' "$mutation" > "$tmp/words-mutated.md"
  ! same_words "$tmp/words-source.md" "$tmp/words-mutated.md" \
    || { echo "word mutation was not detected: $mutation" >&2; exit 1; }
done
grep -q '^description: >-$' "$tmp/a.md" || { echo "long description must be folded" >&2; exit 1; }
grep -q '^argument-hint: "\[x\]"$' "$tmp/a.md" || { echo "short front matter keys must be untouched" >&2; exit 1; }
# heading, table row, and code line are reported, not rewritten
for want in ":[0-9]+:# Demo" ":[0-9]+:\\| col" ":[0-9]+:echo"; do echo "$out" | grep -qE "WIDE: .*$want" || { echo "fix must report remaining hand-work ($want): $out" >&2; exit 1; }; done
grep -q "^| col | $long |$" "$tmp/a.md" || { echo "table rows must be left alone" >&2; exit 1; }
grep -q "^echo \"$long\"$" "$tmp/a.md" || { echo "code lines must be left alone" >&2; exit 1; }
grep -q "^     echo \"indented fence: $long\"$" "$tmp/a.md" || { echo "an indented fence must be left alone" >&2; exit 1; }
grep -q '^   - nested bullet: word' "$tmp/a.md" || { echo "a nested bullet must keep its indent" >&2; exit 1; }
grep -q '^Unindented text after the list starts a new paragraph.$' "$tmp/a.md" || { echo "a less-indented line must not merge into the item" >&2; exit 1; }
# no rewrapped continuation line starts with a list marker, heading, quote, or table pipe
! grep -qE '^[[:space:]]*(\+ caller|- a dash|2\. two|# hash|\| pipe)' "$tmp/a.md" || { echo "a continuation line starts with a marker" >&2; exit 1; }
grep -q 'iota + caller' "$tmp/a.md" || grep -q 'theta iota' "$tmp/a.md" || { echo "marker paragraph lost words" >&2; exit 1; }
# blockquote lines are left alone, never merged into prose
[ "$(grep -c '^> ' "$tmp/a.md")" = 2 ] || { echo "blockquote lines must stay separate" >&2; exit 1; }
# a second fix is a no-op, and a clean file passes check
cp "$tmp/a.md" "$tmp/b.md"; bash "$script" fix "$tmp/b.md" >/dev/null 2>&1 || true; cmp -s "$tmp/a.md" "$tmp/b.md" || { echo "fix must be idempotent" >&2; exit 1; }
printf '# ok\n\nshort line — with a multibyte dash and an arrow → still counted as characters.\n' > "$tmp/c.md"
bash "$script" check "$tmp/c.md" >/dev/null || { echo "a clean file must pass" >&2; exit 1; }
printf '%s\n' "$(printf 'é%.0s' $(seq 1 100))" > "$tmp/d.md"   # 100 characters, 200 bytes
bash "$script" check "$tmp/d.md" >/dev/null || { echo "width must count characters, not bytes" >&2; exit 1; }
echo "width.sh check and fix valid"
