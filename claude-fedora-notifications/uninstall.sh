#!/usr/bin/env bash
# Деинсталлер: снимает хуки из ~/.claude/settings.json, удаляет скрипты и состояние.
set -uo pipefail
DEST="$HOME/.claude/hooks"
STATE="$HOME/.claude/notify-state"
SETTINGS="$HOME/.claude/settings.json"

echo "==> Снятие хуков в $SETTINGS"
if [ -f "$SETTINGS" ]; then
python3 - "$SETTINGS" <<'PY'
import json, os, sys, shutil
sp = sys.argv[1]
OURS = {"notify-linux.sh","notify-pretool.sh","notify-clear.sh","notify-stop.sh"}
try:
    with open(sp, encoding="utf-8") as f: data = json.load(f)
except Exception as e:
    print("  ! settings.json не парсится:", e); sys.exit(0)
hooks = data.get("hooks", {})
for event in list(hooks.keys()):
    groups = []
    for g in hooks[event]:
        g["hooks"] = [h for h in g.get("hooks", [])
                      if os.path.basename(h.get("command","")) not in OURS]
        if g["hooks"]:
            groups.append(g)
    if groups: hooks[event] = groups
    else: del hooks[event]
if not hooks: data.pop("hooks", None)
shutil.copy(sp, sp + ".bak-notif-uninstall")
with open(sp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print("  ✓ хуки сняты (бэкап: %s.bak-notif-uninstall)" % sp)
PY
fi

echo "==> Удаление скриптов и состояния"
rm -f "$DEST"/_notify.sh "$DEST"/_reminder.sh "$DEST"/notify-linux.sh \
      "$DEST"/notify-clear.sh "$DEST"/notify-pretool.sh "$DEST"/notify-stop.sh 2>/dev/null
echo "  ✓ хук-скрипты удалены"
rm -rf "$STATE" 2>/dev/null && echo "  ✓ $STATE удалён"

echo "ГОТОВО. Перезапусти VSCode, чтобы сбросить хуки текущей сессии."
