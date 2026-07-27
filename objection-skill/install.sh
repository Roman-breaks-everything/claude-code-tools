#!/usr/bin/env bash
# Установщик скилла Claude Code "objection": симлинкует скилл-папку в ~/.claude/skills/.
# Идемпотентно. Обновления в репо подхватываются автоматически (симлинк, не копия).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills"

LANG_DIR="objection"
case "${1:-ru}" in
  en|EN|english) LANG_DIR="objection-en" ;;
  ru|RU|"") LANG_DIR="objection" ;;
  *) echo "  ! неизвестный язык '$1' (ожидается ru|en) — ставлю ru"; LANG_DIR="objection" ;;
esac

echo "==> Установка скилла objection ($LANG_DIR)"
mkdir -p "$DEST"
ln -sfn "$HERE/$LANG_DIR" "$DEST/objection"
echo "  ✓ $DEST/objection -> $HERE/$LANG_DIR"

echo "==> Готово. Перезапусти Claude Code (скиллы читаются при старте сессии)."