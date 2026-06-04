#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Create a new portable Codex/Claude Code skill skeleton.

Usage:
  scripts/new-skill.sh <skill-name> [description]

Example:
  scripts/new-skill.sh weekly-report "Weekly report workflow. Use when drafting or reviewing weekly status reports."
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ]; then
  usage
  exit 0
fi

RAW_NAME="$1"
DESCRIPTION="${2:-User-authored skill. Replace this description with what the skill does and when to use it.}"

NAME=$(printf '%s' "$RAW_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')

case "$NAME" in
  ''|*-|-*|*--*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
    printf 'error: invalid skill name after normalization: %s\n' "$NAME" >&2
    exit 1
    ;;
esac

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SKILL_DIR="$ROOT_DIR/skills/$NAME"

if [ -e "$SKILL_DIR" ]; then
  printf 'error: skill already exists: %s\n' "$SKILL_DIR" >&2
  exit 1
fi

TITLE=$(printf '%s' "$NAME" | awk -F- '{ for (i = 1; i <= NF; i++) { $i = toupper(substr($i,1,1)) substr($i,2) } print }')
ESC_DESCRIPTION=$(printf '%s' "$DESCRIPTION" | sed 's/\\/\\\\/g; s/"/\\"/g')
ESC_TITLE=$(printf '%s' "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')

mkdir -p "$SKILL_DIR/agents"

cat > "$SKILL_DIR/SKILL.md" <<EOF
---
name: $NAME
description: "$ESC_DESCRIPTION"
---

# $TITLE

## Overview

Write the core instructions for this skill here.

## Workflow

Replace this section with the reusable workflow the agent should follow.

## Resources

Add supporting files only when useful:

- \`scripts/\` for executable helpers.
- \`references/\` for long docs the agent should read only when needed.
- \`assets/\` for templates or files the agent should copy into outputs.
EOF

cat > "$SKILL_DIR/agents/openai.yaml" <<EOF
interface:
  display_name: "$ESC_TITLE"
  short_description: "$ESC_DESCRIPTION"
  default_prompt: "Use this skill."
EOF

printf 'Created %s\n' "$SKILL_DIR"
