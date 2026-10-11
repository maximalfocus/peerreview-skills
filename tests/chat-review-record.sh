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
want_sha=$(git -C "$ws" cat-file blob "HEAD:REPLY.txt" | shasum -a 256 | awk '{print $1}')
want_verdict_sha=$(shasum -a 256 < "$v" | awk '{print $1}')
python3 - "$out" "$want_sha" "$(git -C "$ws" rev-parse HEAD)" "$want_verdict_sha" <<'PY' || fail "record content"
import datetime, json, os, stat, sys
path, sha, head, verdict_sha = sys.argv[1:5]
rec = json.load(open(path, encoding="utf-8"))
t = datetime.datetime.fromisoformat(rec.pop("time"))
assert t.tzinfo is not None and abs((datetime.datetime.now(t.tzinfo) - t).total_seconds()) < 120, t
assert rec == {"v": 1, "sha256": sha, "verdict_sha256": verdict_sha, "file": "REPLY.txt", "verdict": "CONVERGED", "peer": "codex",
               "head": head, "meta": {"chat": "Group One",
                                      "answers": "wx#2@Group-One/2026-10-11-070000-new.md"}}, rec
assert os.path.basename(path).startswith(sha + "-"), path
assert stat.S_IMODE(os.stat(path).st_mode) == 0o600, oct(os.stat(path).st_mode)
assert stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode) == 0o700
PY
# A no-meta pass proves the generic record has `meta: {}`; whether a consumer accepts it is that
# consumer's rule. Markdown decoration and CRLF are supported in verdict output.
verdict "$v" '## Verdict\n\n**CONVERGED** — no substantive defects remain\n'
python3 - "$v" <<'PY'
import sys
p = sys.argv[1]
with open(p, "rb") as f:
    data = f.read()
with open(p, "wb") as f:
    f.write(data.replace(b"\n", b"\r\n"))
PY
out2=$(bash "$record" "$ws" "$v" pi REPLY.txt)
[ "$out2" != "$out" ] || fail "a second record replaced the first"
python3 -c 'import json, sys
r = json.load(open(sys.argv[1]))
import hashlib
assert r["meta"] == {} and r["peer"] == "pi", r
assert r["verdict_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(), r' \
  "$out2" "$v" || fail "record without meta"
[ "$(count)" = 2 ] || fail "expected 2 records, found $(count)"
ls "$records"/.record.* >/dev/null 2>&1 && fail "a temp record file was left behind"

# every refusal writes nothing
verdict "$v" 'NOT CONVERGED — round 3 needed\n- the reply promises a date\n'
refused "not converged" "the verdict is NOT CONVERGED" "$ws" "$v" codex REPLY.txt
verdict "$v" 'Earlier: CONVERGED\n\n> **NOT CONVERGED** — round 2 needed\nCONVERGED once fixed\n'
refused "both words" "the verdict is NOT CONVERGED" "$ws" "$v" codex REPLY.txt
verdict "$v" 'The draft has CONVERGED in my view.\nCONVERGEDLY\n'
refused "no verdict line" "no CONVERGED verdict line" "$ws" "$v" codex REPLY.txt
verdict "$v" 'CONVERGED? maybe\n'
refused "question verdict" "no CONVERGED verdict line" "$ws" "$v" codex REPLY.txt
verdict "$v" 'CONVERGED: no defects remain\n'
refused "colon verdict" "no CONVERGED verdict line" "$ws" "$v" codex REPLY.txt
verdict "$v" 'CONVERGED*not actually a verdict\n'
refused "asterisk suffix" "no CONVERGED verdict line" "$ws" "$v" codex REPLY.txt
verdict "$v" 'NOT  CONVERGED — still has a finding\nCONVERGED — after a future fix\n'
refused "double-spaced not converged" "the verdict is NOT CONVERGED" "$ws" "$v" codex REPLY.txt
verdict "$v" 'Not converged — findings remain\nCONVERGED — after a future fix\n'
refused "lowercase not converged" "the verdict is NOT CONVERGED" "$ws" "$v" codex REPLY.txt
verdict "$v" '> **NOT CONVERGED** — finding remains\n> CONVERGED — quoted text\n'
refused "quoted converged in not report" "the verdict is NOT CONVERGED" "$ws" "$v" codex REPLY.txt
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
refused "dot-dot component" "the reviewed file is not a committed regular file" \
  "$ws" "$v" codex dir/../REPLY.txt
refused "absolute file" "the reviewed file is not a committed regular file" \
  "$ws" "$v" codex "$ws/REPLY.txt"
printf 'x\n' > "$ws/-dash.txt"
printf 'x\n' > "$ws/A*.txt"
printf 'x\n' > "$ws/AB.txt"
printf '{"dotdot": true}\n' > "$ws/two..dots.txt"
printf 'x\n' > "$ws/"$'line\nbreak.txt'
git -C "$ws" add -- -dash.txt 'A*.txt' AB.txt two..dots.txt $'line\nbreak.txt'
git -C "$ws" commit -qm 'odd path fixtures'
verdict "$v" 'CONVERGED — no substantive defects remain\n'
for odd_path in -dash.txt $'line\nbreak.txt'; do
  refused "special file path $odd_path" "the reviewed file is not a committed regular file" \
    "$ws" "$v" codex "$odd_path"
  refused "special meta path $odd_path" "the meta file is not a committed regular file" \
    "$ws" "$v" codex REPLY.txt "$odd_path"
done
mkdir -p "$ws/DIR"
printf 'x\n' > "$ws/DIR/inside.txt"
git -C "$ws" add DIR
git -C "$ws" commit -qm 'tree and gitlink fixtures'
verdict "$v" 'CONVERGED — no substantive defects remain\n'
refused "tree path" "the reviewed file is not a committed regular file" "$ws" "$v" codex DIR
mkdir "$base/subrepo"
git -C "$base/subrepo" init -q
git -C "$base/subrepo" config user.name Test
git -C "$base/subrepo" config user.email test@example.invalid
printf 'submodule\n' > "$base/subrepo/file"
git -C "$base/subrepo" add file
git -C "$base/subrepo" commit -qm submodule
git -C "$ws" -c protocol.file.allow=always submodule add "$base/subrepo" SUBMODULE >/dev/null
git -C "$ws" commit -qm 'gitlink fixture'
verdict "$v" 'CONVERGED — no substantive defects remain\n'
refused "submodule path" "the reviewed file is not a committed regular file" \
  "$ws" "$v" codex SUBMODULE
refused "untracked meta" "the meta file is not a committed regular file" \
  "$ws" "$v" codex REPLY.txt N.json
refused "glob meta path" "the meta file is not a JSON object" \
  "$ws" "$v" codex REPLY.txt 'A*.txt'
refused "list meta" "the meta file is not a JSON object" "$ws" "$v" codex REPLY.txt LIST.json
refused "broken meta" "the meta file is not a JSON object" "$ws" "$v" codex REPLY.txt BROKEN.json
ls "$records"/.record.* >/dev/null 2>&1 && fail "invalid meta left a temp record"
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
rc=0; home_err=$(env -u HOME bash "$record" "$ws" "$v" codex REPLY.txt 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 65 ] || fail "unset HOME: rc=$rc"
case "$home_err" in *"refused, no record written: HOME is unset"*) ;; *) fail "unset HOME: $home_err" ;; esac
mkdir -p "$(dirname "$records")" "$base/real-records"
mv "$records" "$base/records-backup"
ln -s "$base/real-records" "$records"
refused "record folder symlink" "a record folder path component is a symlink" \
  "$ws" "$v" codex REPLY.txt
rm "$records"
mv "$base/records-backup" "$records"
mv "$records" "$base/records-backup"
: > "$records"
refused "record folder file" "a record folder path component is not a directory" \
  "$ws" "$v" codex REPLY.txt
rm "$records"
mv "$base/records-backup" "$records"
parent_path=$HOME/.local/state/peerreview
mv "$parent_path" "$base/peerreview-backup"
ln -s "$base/peerreview-backup" "$parent_path"
refused "symlinked record parent" "a record folder path component is a symlink" \
  "$ws" "$v" codex REPLY.txt
rm "$parent_path"
mv "$base/peerreview-backup" "$parent_path"
real_stat=$(command -v stat)
mkdir "$base/mockbin"
cat > "$base/mockbin/stat" <<'SH'
#!/bin/sh
case "$*" in
  *%u*) echo 99999 ;;
  *) exec "$REAL_STAT" "$@" ;;
esac
SH
chmod +x "$base/mockbin/stat"
chmod 755 "$records"
rc=0
owner_err=$(REAL_STAT="$real_stat" PATH="$base/mockbin:$PATH" bash "$record" \
  "$ws" "$v" codex REPLY.txt 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 65 ] || fail "foreign-owned record folder: rc=$rc"
case "$owner_err" in *"refused, no record written: the record folder is not owned by this user"*) ;; *) fail "foreign-owned record folder: $owner_err" ;; esac
record_mode=$(python3 -c 'import os, stat, sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$records")
[ "$record_mode" = 755 ] || \
  fail "foreign-owned record folder permissions changed"
chmod 700 "$records"
rc=0; bash "$record" "$ws" "$v" codex >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || fail "usage: rc=$rc"
[ "$(count)" = 2 ] || fail "a refusal wrote a record"
# the last refusal cleared, the same call passes again: the refusals above were not a broken fixture
bash "$record" "$ws" "$v" codex REPLY.txt SEND.json >/dev/null || fail "final pass"
[ "$(count)" = 3 ] || fail "expected 3 records"
# Glob and repeated dots are valid literal filename characters here; the exact Git path must match.
glob_record=$(bash "$record" "$ws" "$v" codex 'A*.txt')
python3 - "$glob_record" <<'PY' || fail "glob path was not treated literally"
import json, sys
assert json.load(open(sys.argv[1]))["file"] == "A*.txt"
PY
[ "$(count)" = 4 ] || fail "glob path record missing"
dot_record=$(bash "$record" "$ws" "$v" codex two..dots.txt)
python3 - "$dot_record" <<'PY' || fail "repeated-dot filename was refused"
import json, sys
assert json.load(open(sys.argv[1]))["file"] == "two..dots.txt"
PY
[ "$(count)" = 5 ] || fail "repeated-dot filename record missing"
dot_meta_record=$(bash "$record" "$ws" "$v" codex REPLY.txt two..dots.txt)
python3 - "$dot_meta_record" <<'PY' || fail "repeated-dot meta filename was refused"
import json, sys
assert json.load(open(sys.argv[1]))["meta"] == {"dotdot": True}
PY

# A tracked verdict output is permitted when its mtime is at least the commit timestamp.
tracked_ws=$(bash "$root/scripts/chat-review-temp.sh" new)
printf 'reply\n' > "$tracked_ws/REPLY.txt"
verdict "$tracked_ws/VERDICT.md" 'CONVERGED — reviewed in the same commit\n'
git -C "$tracked_ws" add REPLY.txt VERDICT.md
GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
  git -C "$tracked_ws" commit -qm 'tracked verdict fixture'
tracked_record=$(bash "$record" "$tracked_ws" "$tracked_ws/VERDICT.md" codex REPLY.txt)
[ -f "$tracked_record" ] || fail "tracked verdict output was refused"

# Pin the limit: after a later commit, refreshing an old verdict mtime still authorizes the new bytes.
stale_ws=$(bash "$root/scripts/chat-review-temp.sh" new)
printf 'old reviewed bytes\n' > "$stale_ws/REPLY.txt"
git -C "$stale_ws" add REPLY.txt
GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
  git -C "$stale_ws" commit -qm reviewed
verdict "$base/stale-verdict" 'CONVERGED — old review\n'
printf 'new unreviewed bytes\n' >> "$stale_ws/REPLY.txt"
git -C "$stale_ws" add REPLY.txt
git -C "$stale_ws" commit -qm unreviewed
touch "$base/stale-verdict"
stale_record=$(bash "$record" "$stale_ws" "$base/stale-verdict" codex REPLY.txt)
python3 - "$stale_record" "$base/stale-verdict" <<'PY' || fail "refreshed stale verdict behavior"
import hashlib, json, sys
rec = json.load(open(sys.argv[1]))
assert rec["verdict_sha256"] == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
assert rec["sha256"] == hashlib.sha256(b"old reviewed bytes\nnew unreviewed bytes\n").hexdigest()
PY

# Plant the exact destination name for the recorder's PID and fixed UTC timestamp.
mkdir "$base/fixed-date"
cat > "$base/fixed-date/date" <<'SH'
#!/bin/sh
printf '20000101T000000Z\n'
SH
chmod +x "$base/fixed-date/date"
collision_rc=0
collision_err=$(PATH="$base/fixed-date:$PATH" bash -c '
set -eu
ws=$1 verdict=$2 record=$3 records=$4
sha=$(git -C "$ws" cat-file blob HEAD:REPLY.txt | shasum -a 256 | awk "{print \$1}")
target=$records/$sha-20000101T000000Z-$$.json
printf sentinel > "$target"
exec bash "$record" "$ws" "$verdict" codex REPLY.txt
' _ "$ws" "$v" "$record" "$records" 2>&1) || collision_rc=$?
[ "$collision_rc" -eq 65 ] || fail "destination collision rc=$collision_rc"
case "$collision_err" in *"record already exists at the destination path"*) ;; *) fail "destination collision: $collision_err" ;; esac
case "$(cat "$records"/*20000101T000000Z-*.json)" in sentinel) ;; *) fail "existing collision record was replaced" ;; esac
ls "$records"/.record.* >/dev/null 2>&1 && fail "destination refusal left a temp record"

printf 'PASS: chat review record\n'
