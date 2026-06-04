#!/usr/bin/env sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SKILLS_DIR="${1:-$ROOT_DIR/skills}"
FAILED=0
FOUND=0

fail() {
  FAILED=1
  printf 'error: %s\n' "$*" >&2
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

valid_skill_name() {
  case "$1" in
    ''|.*|_*|*/*|*' '*|*-|-*|*--*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

[ -d "$SKILLS_DIR" ] || {
  fail "skills directory not found: $SKILLS_DIR"
  exit 1
}

for skill_dir in "$SKILLS_DIR"/*; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  case "$skill_name" in
    .*|_*) continue ;;
  esac
  [ -f "$skill_dir/SKILL.md" ] || continue

  FOUND=$((FOUND + 1))
  skill_md="$skill_dir/SKILL.md"

  if ! valid_skill_name "$skill_name"; then
    fail "invalid skill directory name: $skill_name"
    continue
  fi

  first_line=$(sed -n '1p' "$skill_md")
  [ "$first_line" = "---" ] || fail "$skill_name/SKILL.md must start with ---"
  grep -Eq '^name:[[:space:]]*' "$skill_md" || fail "$skill_name/SKILL.md is missing name:"
  grep -Eq '^description:[[:space:]]*' "$skill_md" || fail "$skill_name/SKILL.md is missing description:"

  if grep -Eq '^[[:space:]]*(disable-model-invocation|user-invocable|argument-hint|arguments|context|agent|hooks|paths|shell|model|effort|when_to_use):' "$skill_md"; then
    warn "$skill_name has Claude-specific frontmatter; keep Codex compatibility in mind"
  fi

  if grep -Eq '\[TODO|TODO:' "$skill_md"; then
    warn "$skill_name still contains TODO text"
  fi

  printf 'ok: %s\n' "$skill_name"
done

[ "$FOUND" -gt 0 ] || fail "no skills found in $SKILLS_DIR"

exit "$FAILED"
