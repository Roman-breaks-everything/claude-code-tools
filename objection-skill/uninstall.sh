#!/usr/bin/env bash
# Удаляет симлинк скилла objection из ~/.claude/skills/.
set -euo pipefail

DEST="$HOME/.claude/skills/objection"
if [ -L "$DEST" ]; then
  rm "$DEST"
  echo "  ✓ удалён симлинк $DEST"
else
  echo "  ! симлинка $DEST нет (нечего удалять)"
fi