#!/usr/bin/env bash
# Applies the agentic-systems kit to a project: copies rules into .claude/rules/ and
# appends the CLAUDE.md snippet. Idempotent: re-running updates unchanged kit files,
# leaves user-modified ones alone, and never appends the snippet twice.
#
# Usage: apply.sh [--dry-run] [--force] [TARGET_DIR]
#   --dry-run   show what would change, change nothing
#   --force     overwrite rule files the user has modified (a .bak copy is kept)
#   TARGET_DIR  project root (default: current directory)
set -euo pipefail

DRY=0; FORCE=0; TARGET=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) TARGET="$a" ;;
  esac
done
TARGET="${TARGET:-$PWD}"
TARGET="$(cd "$TARGET" && pwd)"

ASSETS="$(cd "$(dirname "$0")/../assets" && pwd)"
RULES_SRC="$ASSETS/rules"
SNIPPET="$ASSETS/CLAUDE.md.snippet"
MARKER="## Agentic system design"

RULES_DST="$TARGET/.claude/rules"
CLAUDE_MD="$TARGET/CLAUDE.md"
[ -f "$TARGET/.claude/CLAUDE.md" ] && [ ! -f "$CLAUDE_MD" ] && CLAUDE_MD="$TARGET/.claude/CLAUDE.md"

say() { printf '%s\n' "$*"; }
act() { if [ "$DRY" = 1 ]; then say "  [dry-run] $*"; else say "  $*"; fi; }

say "Target project: $TARGET"
[ "$DRY" = 1 ] && say "(dry run: nothing will be written)"

# ---- rules ------------------------------------------------------------------
say ""
say "Rules -> $RULES_DST"
[ "$DRY" = 1 ] || mkdir -p "$RULES_DST"
changed=0; skipped=0
for src in "$RULES_SRC"/*.md; do
  name="$(basename "$src")"; dst="$RULES_DST/$name"
  if [ ! -f "$dst" ]; then
    act "add     $name"; [ "$DRY" = 1 ] || cp "$src" "$dst"; changed=$((changed+1))
  elif cmp -s "$src" "$dst"; then
    say "  ok      $name (unchanged)"
  else
    # Does the existing file still match a previous kit version? We can't know, so treat as modified.
    if [ "$FORCE" = 1 ]; then
      act "replace $name (backup -> $name.bak)"
      [ "$DRY" = 1 ] || { cp "$dst" "$dst.bak"; cp "$src" "$dst"; }
      changed=$((changed+1))
    else
      say "  keep    $name (differs from kit; use --force to replace, keeps a .bak)"; skipped=$((skipped+1))
    fi
  fi
done

# ---- CLAUDE.md --------------------------------------------------------------
say ""
say "CLAUDE.md -> $CLAUDE_MD"
if [ -f "$CLAUDE_MD" ] && grep -qF "$MARKER" "$CLAUDE_MD"; then
  say "  ok      snippet already present (section '$MARKER')"
else
  if [ -f "$CLAUDE_MD" ]; then
    act "append  snippet to existing CLAUDE.md"
    [ "$DRY" = 1 ] || { printf '\n' >> "$CLAUDE_MD"; cat "$SNIPPET" >> "$CLAUDE_MD"; }
  else
    act "create  CLAUDE.md with the snippet"
    [ "$DRY" = 1 ] || { printf '# Project instructions\n\n' > "$CLAUDE_MD"; cat "$SNIPPET" >> "$CLAUDE_MD"; }
  fi
fi

# ---- plugin enablement (report only) -----------------------------------------
say ""
say "Plugin"
SETTINGS="$TARGET/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q '"agentic-systems@' "$SETTINGS"; then
  say "  ok      agentic-systems is enabled in .claude/settings.json (project scope)"
elif [ -f "$HOME/.claude/settings.json" ] && grep -q '"agentic-systems@' "$HOME/.claude/settings.json"; then
  say "  ok      agentic-systems is enabled in ~/.claude/settings.json (user scope)"
else
  say "  note    agentic-systems is not enabled in project or user settings."
  say "          It is loaded in this session (this script came from it), but to persist it run:"
  say "          claude plugin install agentic-systems@<marketplace> --scope project"
fi

say ""
if [ "$DRY" = 1 ]; then
  say "Dry run: $changed rule file(s) would be written, $skipped would be kept as-is."
else
  say "Done: $changed rule file(s) written, $skipped kept as-is."
fi
