#!/usr/bin/env bash
# The configured Codex CLI homes, in the order select-peer.sh tries them (sourced, not run).
#
# Each home is its own `codex login` (CODEX_HOME holds the auth and the sessions), so a second
# signed-in account can take a review when the first is out of quota. Entries come from the first
# source that is set:
#   1. PEERREVIEW_CODEX_HOMES — one entry per line;
#   2. ${XDG_CONFIG_HOME:-$HOME/.config}/peerreview/codex-homes — one entry per line, `#` comments;
#   3. the default: $HOME/.codex, then $HOME/.codex-b; a CODEX_HOME pointing elsewhere replaces
#      the pair, so a single-home user's own CLI home still works.
# An entry is `<path>` or `<label>=<path>`; a leading `~/` means $HOME. The label is what every
# report names — never the path, which may hold an account name — and defaults to the path's last
# component without its leading dot (~/.codex -> codex, ~/.codex-b -> codex-b). A label must match
# ^[a-z0-9][a-z0-9-]*$ and be unique, or the list is refused.
#
# Nothing here reads a home's contents: whether a home is signed in is `codex login status` under
# that CODEX_HOME (peer-auth.sh), and no auth file is read, printed or copied between homes.

# ch_list — print `<label><TAB><path>` per configured home, in order; return 64 on a bad list.
ch_list() {
  local src entries line label path seen="" n=0 conf
  conf="${XDG_CONFIG_HOME:-$HOME/.config}/peerreview/codex-homes"
  if [ -n "${PEERREVIEW_CODEX_HOMES:-}" ]; then
    src=PEERREVIEW_CODEX_HOMES; entries="$PEERREVIEW_CODEX_HOMES"
  elif [ -f "$conf" ]; then
    # Only a config file carries `#` comments; an env-var path may contain `#`.
    src="the codex-homes config file"; entries="$(sed 's/#.*//' "$conf")" || return 64
  else
    src=default; entries="$HOME/.codex
$HOME/.codex-b"
    case "${CODEX_HOME:-}" in
      ""|"$HOME/.codex"|"$HOME/.codex/"|"$HOME/.codex-b") ;;
      *) entries="$CODEX_HOME" ;;
    esac
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    case "$line" in
      *=*) label="${line%%=*}"; path="${line#*=}" ;;
      *)   path="$line"; label="" ;;
    esac
    case "$path" in "~/"*) path="$HOME/${path#\~/}" ;; esac
    while [ "${#path}" -gt 1 ] && [ "${path%/}" != "$path" ]; do path="${path%/}"; done
    if [ -z "$label" ]; then label="${path##*/}"; label="${label#.}"; fi
    case "$path" in
      /*) ;;
      *) printf 'peerreview: a Codex home in %s is not an absolute path (entry %s).\n' "$src" "$((n + 1))" >&2
         return 64 ;;
    esac
    if ! printf '%s' "$label" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
      printf 'peerreview: a Codex home in %s has no usable label (entry %s): give it as <label>=<path>, label [a-z0-9-].\n' \
        "$src" "$((n + 1))" >&2
      return 64
    fi
    case " $seen " in
      *" $label "*) printf 'peerreview: Codex home label %s appears twice in %s.\n' "$label" "$src" >&2; return 64 ;;
    esac
    seen="$seen $label"; n=$((n + 1))
    printf '%s\t%s\n' "$label" "$path"
  done <<< "$entries"
  [ "$n" -gt 0 ] || { printf 'peerreview: %s names no Codex home.\n' "$src" >&2; return 64; }
}

# ch_path <label> — print the configured path for <label>; return 64 when it is not configured.
ch_path() {
  local want="$1" list label path
  list="$(ch_list)" || return 64
  while IFS="$(printf '\t')" read -r label path; do
    [ "$label" = "$want" ] && { printf '%s\n' "$path"; return 0; }
  done <<< "$list"
  if printf '%s' "$want" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
    printf 'peerreview: Codex home %s is not configured.\n' "$want" >&2
  else
    printf 'peerreview: PEERREVIEW_CODEX_HOME must be a label from CODEX_HOME_LABEL, not a path.\n' >&2
  fi
  return 64
}
