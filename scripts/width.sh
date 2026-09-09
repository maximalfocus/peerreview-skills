#!/usr/bin/env bash
# Bound every line of a skill repository's prose to 100 characters (Article 6).
#
#   width.sh check [FILE...]   list every line over 100 characters; exit 1 if any
#   width.sh fix   [FILE...]   fold long front-matter scalars and rewrap prose paragraphs and
#                              list items at 100 columns, losslessly; then list what still needs
#                              a hand (headings, table rows, code lines), exit 1 if any remain
#
# FILE defaults to skills/*/SKILL.md, CONSTITUTION.md, and CLAUDE.md under the git toplevel.
# Rewrapping never touches front matter beyond folding `description`/`allowed-tools`, fenced
# code, tables, or headings, and it changes no word: a line count that only shrinks because lines
# got longer is not compression, which is why check counts characters, not lines.
set -euo pipefail
usage() { echo "usage: width.sh check|fix [FILE...]" >&2; exit 64; }
[ "$#" -ge 1 ] || usage
mode="$1"; shift
case "$mode" in check|fix) ;; *) usage;; esac
if [ "$#" -eq 0 ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git repository" >&2; exit 1; }
  cd "$root"
  set -- $(ls skills/*/SKILL.md CONSTITUTION.md CLAUDE.md 2>/dev/null)
fi
[ "$#" -ge 1 ] || { echo "No files to check" >&2; exit 1; }

check() { # $@ = files; prints file:line (chars) for every line over 100 characters
  local f wide=0
  for f in "$@"; do
    if LC_ALL=en_US.UTF-8 grep -nE '^.{101,}' "$f" | cut -c1-90 | sed "s#^#WIDE: $f:#"; then wide=1; fi
  done
  return "$wide"
}

if [ "$mode" = check ]; then
  if check "$@"; then echo "width: every line is 100 characters or fewer"; exit 0; fi
  exit 1
fi

for f in "$@"; do
  python3 - "$f" <<'PY'
import re, sys, textwrap
path = sys.argv[1]; W = 100
src = open(path, encoding='utf-8').read()
lines = src.split('\n'); out = []; i = 0; n = len(lines)
LIST = re.compile(r'^(\s*)([-*+]|\d+\.)\s+')
def fence(l): return l.lstrip().startswith('```') or l.lstrip().startswith('~~~')
def block_start(l):
    return (l.startswith('#') or l.lstrip().startswith('|') or l.lstrip().startswith('>') or fence(l)
            or l.strip() == '' or l.startswith('<') or l.startswith('$ARGUMENTS'))
MARKER = re.compile(r'^\s*(?:[-*+]|\d+\.|#|>|\|)(?:\s|$)')
def wrap_safe(text, lead, indent):
    """Wrap so that no continuation line begins with a token Markdown would read as a list
    marker, heading, quote, or table row; such a token is pulled onto the previous line, and if
    that line then overflows, the previous line's last word comes down with the token instead."""
    lines = textwrap.wrap(text, width=W, initial_indent=lead, subsequent_indent=indent,
                          break_long_words=False, break_on_hyphens=False)
    k = 1
    while k < len(lines):
        if MARKER.match(lines[k]):
            body = lines[k].strip(); token, _, rest = body.partition(' ')
            prev = lines[k - 1]
            if len(prev) + 1 + len(token) <= W:
                lines[k - 1] = prev + ' ' + token
                tail = rest
            else:
                head, _, last = prev.rpartition(' ')
                lines[k - 1] = head
                tail = last + ' ' + token + (' ' + rest if rest else '')
            remainder = ' '.join([tail] + [x.strip() for x in lines[k + 1:]])
            lines = lines[:k] + (textwrap.wrap(remainder, width=W, initial_indent=indent, subsequent_indent=indent,
                                               break_long_words=False, break_on_hyphens=False) if remainder.strip() else [])
            continue
        k += 1
    return lines
# front matter: fold only description / allowed-tools when over width
if lines and lines[0] == '---':
    j = 1
    while j < n and lines[j] != '---': j += 1
    fm = []
    for l in lines[1:j]:
        m = re.match(r'^(description|allowed-tools): "?(.*?)"?$', l)
        if m and len(l) > W:
            fm.append(f'{m.group(1)}: >-')
            fm.extend('  ' + w for w in textwrap.wrap(m.group(2), W - 4, break_long_words=False, break_on_hyphens=False))
        else:
            fm.append(l)
    out.extend(['---'] + fm + ['---']); i = j + 1
code = False
while i < n:
    l = lines[i]
    if fence(l):
        code = not code; out.append(l); i += 1; continue
    if code or block_start(l):
        out.append(l); i += 1; continue
    m = LIST.match(l)
    lead = re.match(r'^\s*', l).group(0)
    indent = ' ' * len(m.group(0)) if m else lead
    # A continuation line belongs to this paragraph or item only while it is indented at least as
    # deep as the item's text (a less-indented line starts something else, never merge it).
    block = [l.strip()]; j = i + 1
    while j < n:
        nl = lines[j]
        if block_start(nl) or LIST.match(nl): break
        if len(re.match(r'^\s*', nl).group(0)) < len(indent): break
        block.append(nl.strip()); j += 1
    text = ' '.join(block)
    out.extend(wrap_safe(text, lead, indent))
    i = j
new = '\n'.join(out)
def body(t):  # everything after the front matter, as words: rewrapping must not change a single one
    parts = t.split('\n---\n', 1)
    return (parts[1] if t.startswith('---\n') and len(parts) == 2 else t).split()
if body(new) != body(src):
    sys.exit(f"width: refusing to write {path}: rewrap would change its words")
if new != src:
    open(path, 'w', encoding='utf-8').write(new)
PY
done
echo "width: rewrapped $# file(s); lines still over 100 characters need a hand (heading, table row, code):"
if check "$@"; then echo "width: none — every line is 100 characters or fewer"; exit 0; fi
exit 1
