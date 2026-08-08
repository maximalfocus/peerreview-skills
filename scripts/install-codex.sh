#!/usr/bin/env bash
# Install this repo's skills for Codex.
#
# Supported repo shapes:
#   1. skills/<name>/SKILL.md       -> symlink each skill directory
#   2. ./SKILL.md                   -> symlink the repo root as one skill
#   3. commands/<name>.md only      -> generate Codex skill dirs from commands
#
# Run once per clone:
#   bash scripts/install-codex.sh
#
# Restart Codex after installing so the skill index is refreshed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
DEST_ROOT="$CODEX_HOME/skills"
FORCE=0

REPO_NAME="$(basename "$REPO_ROOT")"
FAMILY="${REPO_NAME%-skills}"

usage() {
  cat <<'EOF'
Usage: scripts/install-codex.sh [--force]

Installs this repo's skills into $CODEX_HOME/skills.

Options:
  --force   Replace existing destination symlinks or directories.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

installed=0
skipped=0
generated=0

yaml_value() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    BEGIN { in_fm = 0 }
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
      exit
    }
  ' "$file"
}

strip_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 2; next }
    fm == 2 || !fm { print }
  ' "$1"
}

install_symlink() {
  local name="$1"
  local source="$2"
  local dest="$DEST_ROOT/$name"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local current_target=""
    if [ -L "$dest" ]; then
      current_target="$(readlink "$dest")"
    fi

    if [ "$current_target" = "$source" ]; then
      echo "Already installed: $name"
      skipped=$((skipped + 1))
      return 0
    fi

    if [ "$FORCE" -ne 1 ]; then
      echo "Skip existing: $dest"
      echo "  Re-run with --force to replace it."
      skipped=$((skipped + 1))
      return 0
    fi

    rm -rf "$dest"
  fi

  ln -s "$source" "$dest"
  echo "Installed: $name -> $dest"
  installed=$((installed + 1))
}

install_generated_command() {
  local command_file="$1"
  local command_name
  command_name="$(basename "$command_file" .md)"

  local skill_name="$FAMILY-$command_name"
  case "$command_name" in
    "$FAMILY"-*) skill_name="$command_name" ;;
  esac

  local dest="$DEST_ROOT/$skill_name"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$FORCE" -ne 1 ]; then
      echo "Skip existing: $dest"
      echo "  Re-run with --force to replace it."
      skipped=$((skipped + 1))
      return 0
    fi
    rm -rf "$dest"
  fi

  local description
  description="$(yaml_value description "$command_file")"
  if [ -z "$description" ]; then
    description="Imported from /$command_name in $REPO_NAME."
  fi

  mkdir -p "$dest"
  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$skill_name"
    printf 'description: |-\n'
    printf '  %s\n' "$description"
    printf 'metadata:\n'
    printf '  source-command: "/%s"\n' "$command_name"
    printf '  source-repo: "%s"\n' "$REPO_NAME"
    printf '%s\n\n' '---'
    printf '# /%s\n\n' "$command_name"
    strip_frontmatter "$command_file"
  } > "$dest/SKILL.md"

  echo "Generated: $skill_name -> $dest"
  installed=$((installed + 1))
  generated=$((generated + 1))
}

mkdir -p "$DEST_ROOT"

if compgen -G "$REPO_ROOT/skills/*/SKILL.md" >/dev/null; then
  for skill_dir in "$REPO_ROOT"/skills/*; do
    [ -d "$skill_dir" ] || continue
    [ -f "$skill_dir/SKILL.md" ] || continue

    name="$(basename "$skill_dir")"
    install_symlink "$name" "$skill_dir"
  done
elif [ -f "$REPO_ROOT/SKILL.md" ]; then
  name="$(yaml_value name "$REPO_ROOT/SKILL.md")"
  [ -n "$name" ] || name="$REPO_NAME"
  install_symlink "$name" "$REPO_ROOT"
elif compgen -G "$REPO_ROOT/commands/*.md" >/dev/null; then
  for command_file in "$REPO_ROOT"/commands/*.md; do
    [ -f "$command_file" ] || continue
    install_generated_command "$command_file"
  done
else
  echo "No Codex-compatible skills found in $REPO_ROOT" >&2
  exit 1
fi

echo
echo "Codex skills directory: $DEST_ROOT"
echo "Installed: $installed, generated: $generated, skipped: $skipped"
echo "Restart Codex to pick up new skills."
