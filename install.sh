#!/usr/bin/env sh
set -eu

DEFAULT_REPO="mizuamedesu/ReportSkills"
DEFAULT_REF="main"
SKILLS_SUBDIR="${SKILLS_SUBDIR:-skills}"

REPO="${REPO:-$DEFAULT_REPO}"
REF="${REF:-$DEFAULT_REF}"
TARGETS="${INSTALL_TARGETS:-both}"
SOURCE_DIR="${SOURCE_DIR:-}"
DRY_RUN=0
BACKUP=1
TMP_DIR=""

usage() {
  cat <<'EOF'
Install ReportSkills into Codex and/or Claude Code.

Usage:
  sh install.sh [options]

Options:
  --codex-only        Install only to Codex
  --claude-only       Install only to Claude Code
  --targets LIST      comma-separated: codex,claude,both
  --repo OWNER/REPO   GitHub repository to download when not run locally
  --ref REF           Git ref to download when not run locally
  --source DIR        Local repository directory containing skills/
  --no-backup         Replace existing skills without creating .bak copies
  --dry-run           Show what would be installed
  -h, --help          Show this help

Environment:
  INSTALL_TARGETS     codex, claude, or both
  CODEX_SKILLS_DIR    Override Codex skills destination
  CLAUDE_SKILLS_DIR   Override Claude Code skills destination
  REPO                GitHub OWNER/REPO for remote install
  REF                 Git ref for remote install
EOF
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --codex-only)
      TARGETS="codex"
      ;;
    --claude-only)
      TARGETS="claude"
      ;;
    --targets)
      [ "$#" -ge 2 ] || die "--targets requires a value"
      TARGETS="$2"
      shift
      ;;
    --repo)
      [ "$#" -ge 2 ] || die "--repo requires a value"
      REPO="$2"
      shift
      ;;
    --ref)
      [ "$#" -ge 2 ] || die "--ref requires a value"
      REF="$2"
      shift
      ;;
    --source)
      [ "$#" -ge 2 ] || die "--source requires a value"
      SOURCE_DIR="$2"
      shift
      ;;
    --no-backup)
      BACKUP=0
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

case "$TARGETS" in
  both|all)
    WANT_CODEX=1
    WANT_CLAUDE=1
    ;;
  codex)
    WANT_CODEX=1
    WANT_CLAUDE=0
    ;;
  claude)
    WANT_CODEX=0
    WANT_CLAUDE=1
    ;;
  codex,claude|claude,codex)
    WANT_CODEX=1
    WANT_CLAUDE=1
    ;;
  *)
    die "invalid targets: $TARGETS"
    ;;
esac

CODEX_DEST="${CODEX_SKILLS_DIR:-${CODEX_HOME:-$HOME/.codex}/skills}"
CLAUDE_DEST="${CLAUDE_SKILLS_DIR:-${CLAUDE_HOME:-$HOME/.claude}/skills}"

script_dir() {
  case "$0" in
    */*) dirname "$0" ;;
    *) printf '.' ;;
  esac
}

resolve_source() {
  if [ -n "$SOURCE_DIR" ]; then
    [ -d "$SOURCE_DIR/$SKILLS_SUBDIR" ] || die "no $SKILLS_SUBDIR/ directory in $SOURCE_DIR"
    printf '%s/%s\n' "$SOURCE_DIR" "$SKILLS_SUBDIR"
    return
  fi

  if [ -f "$0" ]; then
    SCRIPT_DIR=$(cd "$(script_dir)" 2>/dev/null && pwd || printf '.')
    if [ -d "$SCRIPT_DIR/$SKILLS_SUBDIR" ]; then
      printf '%s/%s\n' "$SCRIPT_DIR" "$SKILLS_SUBDIR"
      return
    fi
  fi

  need_command curl
  need_command tar
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/report-skills.XXXXXX")
  ARCHIVE="$TMP_DIR/repo.tar.gz"
  URL="https://codeload.github.com/$REPO/tar.gz/$REF"

  warn "downloading $REPO@$REF"
  curl -fsSL "$URL" -o "$ARCHIVE"
  tar -xzf "$ARCHIVE" -C "$TMP_DIR"
  ROOT_DIR=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  [ -n "$ROOT_DIR" ] || die "downloaded archive did not contain a directory"
  [ -d "$ROOT_DIR/$SKILLS_SUBDIR" ] || die "downloaded archive does not contain $SKILLS_SUBDIR/"
  printf '%s/%s\n' "$ROOT_DIR" "$SKILLS_SUBDIR"
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

validate_skill() {
  skill_dir="$1"
  skill_name="$2"
  skill_md="$skill_dir/SKILL.md"

  valid_skill_name "$skill_name" || die "invalid skill directory name: $skill_name"
  [ -f "$skill_md" ] || die "$skill_name is missing SKILL.md"
  first_line=$(sed -n '1p' "$skill_md")
  [ "$first_line" = "---" ] || die "$skill_name/SKILL.md must start with YAML frontmatter"
  grep -Eq '^name:[[:space:]]*' "$skill_md" || die "$skill_name/SKILL.md is missing name:"
  grep -Eq '^description:[[:space:]]*' "$skill_md" || die "$skill_name/SKILL.md is missing description:"

  if grep -Eq '^[[:space:]]*(disable-model-invocation|user-invocable|argument-hint|arguments|context|agent|hooks|paths|shell|model|effort|when_to_use):' "$skill_md"; then
    warn "$skill_name uses Claude-specific frontmatter; install to Codex only if you have verified compatibility"
  fi
}

install_one() {
  skill_dir="$1"
  skill_name="$2"
  dest_root="$3"
  label="$4"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would install $skill_name to $label: $dest_root/$skill_name"
    return
  fi

  mkdir -p "$dest_root"
  staging="$dest_root/.$skill_name.tmp.$$"
  rm -rf "$staging"
  mkdir -p "$staging"
  (cd "$skill_dir" && tar -cf - .) | (cd "$staging" && tar -xf -)

  if [ -d "$dest_root/$skill_name" ]; then
    if [ "$BACKUP" -eq 1 ]; then
      backup="$dest_root/$skill_name.bak.$(date +%Y%m%d%H%M%S)"
      mv "$dest_root/$skill_name" "$backup"
      log "Backed up $label $skill_name to $backup"
    else
      rm -rf "$dest_root/$skill_name"
    fi
  fi

  mv "$staging" "$dest_root/$skill_name"
  log "Installed $skill_name to $label: $dest_root/$skill_name"
}

SRC=$(resolve_source)
[ -d "$SRC" ] || die "skills source not found: $SRC"

FOUND=0
for skill_dir in "$SRC"/*; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  case "$skill_name" in
    .*|_*) continue ;;
  esac
  [ -f "$skill_dir/SKILL.md" ] || continue
  validate_skill "$skill_dir" "$skill_name"
  FOUND=$((FOUND + 1))
done

[ "$FOUND" -gt 0 ] || die "no installable skills found in $SRC"

for skill_dir in "$SRC"/*; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  case "$skill_name" in
    .*|_*) continue ;;
  esac
  [ -f "$skill_dir/SKILL.md" ] || continue

  if [ "$WANT_CODEX" -eq 1 ]; then
    install_one "$skill_dir" "$skill_name" "$CODEX_DEST" "Codex"
  fi
  if [ "$WANT_CLAUDE" -eq 1 ]; then
    install_one "$skill_dir" "$skill_name" "$CLAUDE_DEST" "Claude Code"
  fi
done

log "Done. Restart Codex or Claude Code if the new skill does not appear immediately."
