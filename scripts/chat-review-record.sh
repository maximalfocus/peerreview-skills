#!/usr/bin/env bash
# Record one CONVERGED chat review so a tool can act on the reviewed file after the
# ephemeral workspace is gone (a reviewed message sent without a per-send confirmation).
# Run by the HOST right after the PEER's verdict and before `chat-review-temp.sh clean`.
# Usage: chat-review-record.sh <chat_workspace> <verdict_out> <peer> <file> [<meta_json>]
#   <verdict_out>  the file the round driver wrote for the --verdict round
#   <peer>         the PEER that returned it, as select-peer.sh named it (codex, claude, pi, dsh)
#   <file>         the reviewed file, committed in the workspace; its committed bytes are hashed
#   <meta_json>    optional committed JSON object the consuming tool reads (e.g. the chat)
# It refuses (and writes nothing) unless the workspace is one chat-review-temp.sh made, its
# tracked tree is clean, <file> and <meta_json> are committed regular files, and
# <verdict_out> is newer than the reviewed commit and holds a CONVERGED verdict line and no
# NOT CONVERGED line. It prints the record's path:
#   ~/.local/state/peerreview/chat-converged/<sha256>-<utc time>-<pid>.json
#   {"v":1,"sha256":…,"file":…,"verdict":"CONVERGED","peer":…,"time":…,"head":…,"meta":{…}}
# Exit 64 usage, 65 a refused input, 1 anything else.
set -euo pipefail

[ "$#" -eq 4 ] || [ "$#" -eq 5 ] || { sed -n '5p' "$0" | cut -c3- >&2; exit 64; }
ws=$1 verdict=$2 peer=$3 file=$4 meta=${5:-}
refuse() { printf 'chat-review-record: refused, no record written: %s\n' "$1" >&2; exit 65; }

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
  case "$1" in ''|/*|-*|*..*) return 1 ;; esac
  row=$(git -C "$resolved" ls-tree HEAD -- "$1") || return 1
  [[ $row == 100644\ blob\ * || $row == 100755\ blob\ * ]] && [[ ${row#*$'\t'} == "$1" ]]
}
committed "$file" || refuse "the reviewed file is not a committed regular file of the workspace"
[ -z "$meta" ] || committed "$meta" || refuse "the meta file is not a committed regular file"

[[ -f $verdict && ! -L $verdict ]] || refuse "the verdict output is not a regular file"
commit_time=$(git -C "$resolved" log -1 --format=%ct HEAD)
verdict_time=$(stat -f %m "$verdict" 2>/dev/null || stat -c %Y "$verdict")
[ "$verdict_time" -ge "$commit_time" ] ||
  refuse "the verdict output is older than the reviewed commit"
# A verdict line starts with the word, after markdown emphasis, a quote mark or a heading mark.
lines=$(sed -E 's/^[[:space:]>#*_`-]+//' "$verdict")
if printf '%s\n' "$lines" | grep -Eq '^NOT CONVERGED([^A-Za-z0-9_]|$)'; then
  refuse "the verdict is NOT CONVERGED"
fi
printf '%s\n' "$lines" | grep -Eq '^CONVERGED([^A-Za-z0-9_]|$)' ||
  refuse "no CONVERGED verdict line"

if command -v shasum >/dev/null 2>&1; then sum=(shasum -a 256); else sum=(sha256sum); fi
sha=$(git -C "$resolved" cat-file blob "HEAD:$file" | "${sum[@]}" | awk '{print $1}')
[[ $sha =~ ^[0-9a-f]{64}$ ]] || { echo "chat-review-record: could not hash the file" >&2; exit 1; }

dir=$HOME/.local/state/peerreview/chat-converged
umask 077
mkdir -p "$dir"
chmod 700 "$dir"
out=$dir/$sha-$(date -u +%Y%m%dT%H%M%SZ)-$$.json
tmp=$(mktemp "$dir/.record.XXXXXX")
trap 'rm -f "$tmp"' EXIT
if [ -n "$meta" ]; then git -C "$resolved" cat-file blob "HEAD:$meta"; else printf '{}'; fi |
  python3 -c '
import datetime, json, sys
sha, name, peer, head = sys.argv[1:5]
try:
    meta = json.load(sys.stdin)
except ValueError:
    meta = None
if not isinstance(meta, dict):
    sys.exit(65)
now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
json.dump({"v": 1, "sha256": sha, "file": name, "verdict": "CONVERGED", "peer": peer,
           "time": now, "head": head, "meta": meta}, sys.stdout, ensure_ascii=False)
sys.stdout.write("\n")
' "$sha" "$file" "$peer" "$head" > "$tmp" || {
    rc=$?
    [ "$rc" -eq 65 ] && refuse "the meta file is not a JSON object"
    echo "chat-review-record: could not write the record" >&2; exit 1; }
mv "$tmp" "$out"
trap - EXIT
printf '%s\n' "$out"
