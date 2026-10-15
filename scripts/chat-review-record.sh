#!/usr/bin/env bash
# Record one CONVERGED chat review so a tool can act on the reviewed file after the
# ephemeral workspace is gone (a reviewed message sent without a per-send confirmation).
# The verdict is bound only by its mtime being at least the commit time: refreshing or
# hand-writing its text defeats that check. Records evidence a review only when the skill ran.
# The peer name is what the HOST passes; it is not independently authenticated here.
# Run by the HOST right after the PEER's verdict and before `chat-review-temp.sh clean`.
# Usage: chat-review-record.sh <chat_workspace> <verdict_out> <peer> <file> [<meta_json>]
#   <verdict_out>  the file the round driver wrote for the --verdict round
#   <peer>         the PEER name supplied by the HOST (typically codex, claude, pi, or dsh)
#   <file>         committed file whose bytes are hashed
#   <meta_json>    optional committed JSON object the consuming tool reads (e.g. the chat)
# <file> and <meta_json> are exact workspace-root-relative paths: nonempty, not absolute, no
# leading dash, newline, . or .. component, or trailing slash. A later component may start '-'.
# When given, <meta_json> must be a committed JSON object; consumers decide which fields they need.
# It checks for a chat-review-temp path and marker (provenance depends on the skill running), a
# clean tracked tree, committed regular files at those paths, and a regular verdict file not older
# than the commit. A line must start with the CONVERGED token (case-sensitive, Markdown markers
# allowed), and no line may start with NOT CONVERGED (case-insensitive, whitespace-normalized).
# With HOME set and no symlink or non-directory below HOME in the record path, it uses an owned
# folder with mode 700, writes a mode 600 record atomically, and refuses an existing destination
# name.
# It prints the record's path:
#   ~/.local/state/peerreview/chat-converged/<sha256>-<utc time>-<pid>.json
#   {"v":1,"sha256":…,"verdict_sha256":…,"file":…,"verdict":"CONVERGED","peer":…,
#    "time":…,"head":…,"meta":{…}}
# Exit 64 usage, 65 a refused input, 1 anything else.
set -euo pipefail

refuse() { printf 'chat-review-record: refused, no record written: %s\n' "$1" >&2; exit 65; }
[ "$#" -eq 4 ] || [ "$#" -eq 5 ] || {
  sed -n '/^# Usage: /s/^# //p' "$0" >&2
  exit 64
}
ws=$1 verdict=$2 peer=$3 file=$4 meta=
if [ "$#" -eq 5 ]; then
  meta=$5
  [[ -n $meta ]] || refuse "the meta path is empty"
fi

root=${TMPDIR:-/tmp}
root=${root%/}
resolved=$(cd "$ws" 2>/dev/null && pwd -P) || refuse "no such chat-review workspace"
root_p=$(cd "$root" 2>/dev/null && pwd -P) || root_p=$root
case "$resolved" in
  "$root_p"/peerreview-chat.*|"$root"/peerreview-chat.*) ;;
  *) refuse "not a peerreview chat workspace path" ;;
esac
owned=$resolved/.peerreview-chat-owned
[[ -f $owned && ! -L $owned ]] || refuse "not a workspace chat-review-temp.sh made"
[[ $peer =~ ^[a-z0-9][a-z0-9-]*$ ]] || refuse "the peer name is not a driver name"

head=$(git -C "$resolved" rev-parse --verify -q HEAD) || refuse "the workspace has no commit"
[ -z "$(git -C "$resolved" status --porcelain --untracked-files=no)" ] ||
  refuse "the workspace's tracked files differ from the reviewed commit"
committed() {  # a regular file at HEAD, named by its path from the workspace root
  local row
  case "$1" in ''|/*|-*|..|../*|*/..|*/../*|.|./*|*/.|*/./*|*/) return 1 ;; esac
  [[ $1 != *$'\n'* ]] || return 1
  row=$(git -C "$resolved" ls-tree HEAD -- ":(literal)$1") || return 1
  [[ $row == 100644\ blob\ * || $row == 100755\ blob\ * ]] && [[ ${row#*$'\t'} == "$1" ]]
}
committed "$file" || refuse "the file is not a committed regular file at an accepted relative path"
[ -z "$meta" ] || committed "$meta" ||
  refuse "the meta file is not a committed regular file at an accepted relative path"

[[ -f $verdict && ! -L $verdict ]] || refuse "the verdict output is not a regular file"
commit_time=$(git -C "$resolved" log -1 --format=%ct HEAD)
verdict_time=$(stat -f %m "$verdict" 2>/dev/null || stat -c %Y "$verdict")
[ "$verdict_time" -ge "$commit_time" ] ||
  refuse "the verdict output is older than the reviewed commit"
# A verdict line starts with its exact verdict token (optionally Markdown-wrapped).
lines=$(tr -d '\r' < "$verdict" | sed -E 's/^[[:space:]>#*_`-]+//; s/[[:space:]]+/ /g')
if printf '%s\n' "$lines" | grep -Ei '^NOT CONVERGED([^A-Za-z0-9_]|$)' >/dev/null; then
  refuse "the verdict is NOT CONVERGED"
fi
printf '%s\n' "$lines" | grep -E '^CONVERGED(\*{1,2}|_{1,2})?([[:space:]]|$)' >/dev/null ||
  refuse "no CONVERGED verdict line"

if command -v shasum >/dev/null 2>&1; then sum=(shasum -a 256); else sum=(sha256sum); fi
sha=$(git -C "$resolved" cat-file blob "HEAD:$file" | "${sum[@]}" | awk '{print $1}')
[[ $sha =~ ^[0-9a-f]{64}$ ]] || { echo "chat-review-record: could not hash the file" >&2; exit 1; }
verdict_sha=$("${sum[@]}" < "$verdict" | awk '{print $1}')
[[ $verdict_sha =~ ^[0-9a-f]{64}$ ]] ||
  { echo "chat-review-record: could not hash the verdict" >&2; exit 1; }

[[ -n ${HOME:-} ]] || refuse "HOME is unset"
dir=$HOME/.local/state/peerreview/chat-converged
parent=$HOME
for part in .local state peerreview chat-converged; do
  parent=$parent/$part
  [[ ! -L $parent ]] || refuse "a record folder path component is a symlink"
  [[ ! -e $parent || -d $parent ]] || refuse "a record folder path component is not a directory"
done
umask 077
mkdir -p "$dir"
parent=$HOME
for part in .local state peerreview chat-converged; do
  parent=$parent/$part
  [[ ! -L $parent ]] || refuse "a record folder path component is a symlink"
done
[[ -d $dir ]] || refuse "the record folder is not a directory"
owner=$(stat -f %u "$dir" 2>/dev/null || stat -c %u "$dir")
[[ $owner == "$(id -u)" ]] || refuse "the record folder is not owned by this user"
chmod 700 "$dir"
out=$dir/$sha-$(date -u +%Y%m%dT%H%M%SZ)-$$.json
tmp=$(mktemp "$dir/.record.XXXXXX")
trap 'rm -f "$tmp"' EXIT
if [ -n "$meta" ]; then git -C "$resolved" cat-file blob "HEAD:$meta"; else printf '{}'; fi |
  python3 -c '
import datetime, json, sys
sha, verdict_sha, name, peer, head = sys.argv[1:6]
try:
    meta = json.load(sys.stdin)
except ValueError:
    meta = None
if not isinstance(meta, dict):
    sys.exit(65)
now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
json.dump({"v": 1, "sha256": sha, "verdict_sha256": verdict_sha, "file": name,
           "verdict": "CONVERGED", "peer": peer, "time": now, "head": head,
           "meta": meta}, sys.stdout, ensure_ascii=False)
sys.stdout.write("\n")
' "$sha" "$verdict_sha" "$file" "$peer" "$head" > "$tmp" || {
    rc=$?
    [ "$rc" -eq 65 ] && refuse "the meta file is not a JSON object"
    echo "chat-review-record: could not write the record" >&2; exit 1; }
if ! python3 -c 'import os, sys; os.link(sys.argv[1], sys.argv[2])' \
  "$tmp" "$out" 2>/dev/null; then
  if [[ -e $out || -L $out ]]; then
    refuse "a record already exists at the destination path"
  fi
  echo "chat-review-record: could not install the record" >&2
  exit 1
fi
rm "$tmp"
trap - EXIT
printf '%s\n' "$out"
