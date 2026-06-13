#!/usr/bin/env bash
# Installer for the self-learning-agent skill.
# Drops the skill into the right place for whichever agent you use.
#
#   ./install.sh                 # install as a Claude Code skill (default)
#   ./install.sh claude          # ~/.claude/skills/self-learning-agent/
#   ./install.sh copilot         # ~/.copilot/skills/self-learning-agent/
#   ./install.sh project [DIR]   # copy AGENTS.md + skill files into a project (default: cwd)
#   ./install.sh help

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="self-learning-agent"
TARGET="${1:-claude}"

copy_skill() {  # $1 = destination skill dir
  local dest="$1"
  mkdir -p "$dest"
  cp "$SRC/SKILL.md" "$SRC/reference.md" "$dest/"
  echo "Installed skill files -> $dest"
}

case "$TARGET" in
  claude)
    copy_skill "${CLAUDE_HOME:-$HOME/.claude}/skills/$SKILL_NAME"
    echo "Restart your Claude Code session (or run /skills) to pick it up."
    ;;
  copilot)
    copy_skill "$HOME/.copilot/skills/$SKILL_NAME"
    echo "Copilot CLI auto-discovers skills from this directory."
    ;;
  project)
    DEST="${2:-$PWD}"
    mkdir -p "$DEST/$SKILL_NAME"
    cp "$SRC/SKILL.md" "$SRC/reference.md" "$DEST/$SKILL_NAME/"
    cp "$SRC/AGENTS.md" "$DEST/$SKILL_NAME/AGENTS.md"
    echo "Copied skill into $DEST/$SKILL_NAME/"
    echo "Codex / Cursor / Zed / Aider / Gemini read AGENTS.md; point yours at $SKILL_NAME/AGENTS.md"
    echo "or paste its 'When this applies' line into your root AGENTS.md / GEMINI.md / CLAUDE.md."
    ;;
  help|-h|--help)
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    echo "Run: ./install.sh help" >&2
    exit 1
    ;;
esac
