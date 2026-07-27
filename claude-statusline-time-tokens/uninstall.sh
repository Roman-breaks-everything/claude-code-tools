#!/usr/bin/env bash
# Удаляет дашборд Claude Code из ~/.claude/hooks/ и снимает старую "часовую"
# statusLine из settings.json (только если она наша). Идемпотентно.
set -uo pipefail

DEST="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

echo "==> Удаление скриптов из $DEST"
for f in dash-statusline.sh statusline.sh watch-statusline.sh; do
  if [ -e "$DEST/$f" ]; then rm -f "$DEST/$f"; echo "  ✓ удалён $DEST/$f"; fi
done

echo "==> Снятие старой statusLine с часами в $SETTINGS"
if [ -f "$SETTINGS" ]; then
python3 - "$SETTINGS" <<'PY'
import json, os, sys, shutil
sp = sys.argv[1]
try:
    with open(sp, encoding="utf-8") as f: data = json.load(f)
except Exception as e:
    print("  ! settings.json не парсится:", e); sys.exit(0)
cur = data.get("statusLine")
if isinstance(cur, dict) and os.path.basename(str(cur.get("command", ""))) == "statusline.sh":
    shutil.copy(sp, sp + ".bak-statusline-uninstall")
    data.pop("statusLine", None)
    with open(sp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("  ✓ statusLine с часами снят (бэкап: %s.bak-statusline-uninstall)" % sp)
else:
    print("  ! statusLine не наш или отсутствует — не трогаю")
PY
fi

echo "ГОТОВО."
