#!/usr/bin/env bash
# chat-review-record.sh: the one pass path and every refusal. HOME and TMPDIR are temp
# folders, so no real state is read or written.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base="$(mktemp -d "${TMPDIR:-/tmp}/peerreview-record-test.XXXXXX")"
trap 'rm -rf "$base"' EXIT
mkdir -p "$base/home" "$base/tmp"
export HOME="$base/home" TMPDIR="$base/tmp"
record="$root/scripts/chat-review-record.sh"
records="$HOME/.local/state/peerreview/chat-converged"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

new_ws() {  # a chat workspace with a committed reply and meta file; prints its path
  local ws
  ws=$(bash "$root/scripts/chat-review-temp.sh" new)
  printf '收到，周一导入后回复。\n' > "$ws/REPLY.txt"
  printf '{"chat": "Group One", "answers": "wx#2@Group-One/2026-10-11-070000-new.md"}\n' \
    > "$ws/SEND.json"
  printf '[1]\n' > "$ws/LIST.json"
  printf 'not json\n' > "$ws/BROKEN.json"
  ln -s REPLY.txt "$ws/LINK.txt"
  git -C "$ws" add REPLY.txt SEND.json LIST.json BROKEN.json LINK.txt
  git -C "$ws" commit -qm baseline
  printf '%s\n' "$ws"
}
verdict() { printf '%b' "$2" > "$1"; }  # path, text
count() { find "$records" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
refused() {  # label, expected reason, then the script's arguments
  local label=$1 want=$2 before rc=0 err
  shift 2
  before=$(count)
  err=$(bash "$record" "$@" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 65 ] || fail "$label: rc=$rc ($err)"
  case "$err" in *"refused, no record written: $want"*) ;; *) fail "$label: said [$err]" ;; esac
  [ "$(count)" = "$before" ] || fail "$label: a record was written"
}

ws=$(new_ws)
v="$base/verdict.md"
verdict "$v" 'No findings.\n\nCONVERGED — no substantive defects remain\n'

# pass, with a meta file
out=$(bash "$record" "$ws" "$v" codex REPLY.txt SEND.json)
case "$out" in "$records"/*.json) ;; *) fail "record path: $out" ;; esac
want_sha=$(shasum -a 256 "$ws/REPLY.txt" | awk '{print $1}')
python3 - "$out" "$want_sha" "$(git -C "$ws" rev-parse HEAD)" <<'PY' || fail "record content"
import datetime, json, os, stat, sys
path, sha, head = sys.argv[1:4]
rec = json.load(open(path, encoding="utf-8"))
t = datetime.datetime.fromisoformat(rec.pop("time"))
assert t.tzinfo is not None and abs((datetime.datetime.now(t.tzinfo) - t).total_seconds()) < 120, t
assert rec == {"v": 1, "sha256": sha, "file": "REPLY.txt", "verdict": "CONVERGED", "peer": "codex",
               "head": head, "meta": {"chat": "Group One",
                                      "answers": "wx#2@Group-One/2026-10-11-070000-new.md"}}, rec
assert os.path.basename(path).startswith(sha + "-"), path
assert stat.S_IMODE(os.stat(path).st_mode) == 0o600, oct(os.stat(path).st_mode)
assert stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode) == 0o700
PY
# pass, without a meta file: an empty meta object; markdown around the verdict word is accepted
verdict "$v" '## Verdict\n\n**CONVERGED** — no substantive defects remain\n'
out2=$(bash "$record" "$ws" "$v" pi REPLY.txt)
[ "$out2" != "$out" ] || fail "a second record replaced the first"
python3 -c 'import json, sys
r = json.load(open(sys.argv[1]))
assert r["meta"] == {} and r["peer"] == "pi", r' "$out2" || fail "record without meta"
[ "$(count)" = 2 ] || fail "expected 2 records, found $(count)"
ls "$records"/.record.* >/dev/null 2>&1 && fail "a temp record file was left behind"

# every refusal writes nothing
verdict "$v" 'NOT CONVERGED — round 3 needed\n- the reply promises a date\n'
refused "not converged" "the verdict is NOT CONVERGED" "$ws" "$v" codex REPLY.txt
verdict "$v" 'Earlier: CONVERGED\n\n> **NOT CONVERGED** — round 2 needed\nCONVERGED once fixed\n'
refused "both words" "the verdict is NOT CONVERGED" "$ws" "$v" codex REPLY.txt
verdict "$v" 'The draft has CONVERGED in my view.\nCONVERGEDLY\n'
refused "no verdict line" "no CONVERGED verdict line" "$ws" "$v" codex REPLY.txt
: > "$v"
refused "empty verdict" "no CONVERGED verdict line" "$ws" "$v" codex REPLY.txt
verdict "$v" 'CONVERGED — no substantive defects remain\n'
refused "missing verdict" "the verdict output is not a regular file" \
  "$ws" "$base/none" codex REPLY.txt
ln -s "$v" "$base/verdict-link"
refused "linked verdict" "the verdict output is not a regular file" \
  "$ws" "$base/verdict-link" codex REPLY.txt
touch -t 200001010000 "$v"
refused "old verdict" "the verdict output is older than the reviewed commit" \
  "$ws" "$v" codex REPLY.txt
touch "$v"
refused "bad peer" "the peer name is not a driver name" "$ws" "$v" 'codex"x' REPLY.txt
refused "untracked file" "the reviewed file is not a committed regular file" \
  "$ws" "$v" codex NONE.txt
refused "linked file" "the reviewed file is not a committed regular file" "$ws" "$v" codex LINK.txt
refused "path escape" "the reviewed file is not a committed regular file" "$ws" "$v" codex ../x
refused "absolute file" "the reviewed file is not a committed regular file" \
  "$ws" "$v" codex "$ws/REPLY.txt"
refused "untracked meta" "the meta file is not a committed regular file" \
  "$ws" "$v" codex REPLY.txt N.json
refused "list meta" "the meta file is not a JSON object" "$ws" "$v" codex REPLY.txt LIST.json
refused "broken meta" "the meta file is not a JSON object" "$ws" "$v" codex REPLY.txt BROKEN.json
printf 'P.S.\n' >> "$ws/REPLY.txt"
refused "edited after the review" "the workspace's tracked files differ" "$ws" "$v" codex REPLY.txt
git -C "$ws" checkout -q -- REPLY.txt
rm "$ws/.peerreview-chat-owned"
refused "unowned workspace" "not a workspace chat-review-temp.sh made" "$ws" "$v" codex REPLY.txt
: > "$ws/.peerreview-chat-owned"
mkdir "$base/elsewhere"
git -C "$base/elsewhere" init -q
: > "$base/elsewhere/.peerreview-chat-owned"
refused "other path" "not a peerreview chat workspace path" "$base/elsewhere" "$v" codex REPLY.txt
refused "missing workspace" "no such chat-review workspace" \
  "$base/tmp/peerreview-chat.none" "$v" codex R
empty=$(bash "$root/scripts/chat-review-temp.sh" new)
refused "no commit" "the workspace has no commit" "$empty" "$v" codex REPLY.txt
rc=0; bash "$record" "$ws" "$v" codex >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "usage: rc=$rc"
[ "$(count)" = 2 ] || fail "a refusal wrote a record"
# the last refusal cleared, the same call passes again: the refusals above were not a broken fixture
bash "$record" "$ws" "$v" codex REPLY.txt SEND.json >/dev/null || fail "final pass"
[ "$(count)" = 3 ] || fail "expected 3 records"

printf 'PASS: chat review record\n'
