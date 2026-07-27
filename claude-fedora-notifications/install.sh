#!/usr/bin/env bash
# Установщик нативных KDE/Plasma-уведомлений для Claude Code на Fedora.
# Копирует хук-скрипты в ~/.claude/hooks/ и регистрирует хуки в ~/.claude/settings.json.
# Идемпотентно: повторный запуск не плодит дубли. Чужие хуки не трогает.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/hooks"
STATE="$HOME/.claude/notify-state"
SETTINGS="$HOME/.claude/settings.json"

echo "==> Проверка окружения"
ok=1
command -v python3 >/dev/null 2>&1 || { echo "  ✗ python3 не найден"; ok=0; }
command -v gdbus   >/dev/null 2>&1 || { echo "  ✗ gdbus не найден (dnf install glib2)"; ok=0; }
command -v setsid  >/dev/null 2>&1 || { echo "  ✗ setsid не найден (dnf install util-linux)"; ok=0; }
[ "$ok" = 1 ] || { echo "Установка прервана — поставь недостающее и повтори."; exit 1; }
echo "  ✓ python3 / gdbus / setsid"

# Проверяем, что служба уведомлений отвечает на шине (KDE Plasma / любой DE).
if gdbus call --session --dest org.freedesktop.Notifications \
     --object-path /org/freedesktop/Notifications \
     --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
  echo "  ✓ org.freedesktop.Notifications отвечает"
else
  echo "  ! org.freedesktop.Notifications не ответила на Ping — уведомления могут не прийти."
  echo "    (проверь, что графическая сессия активна; продолжаю установку)"
fi

echo "==> Копирование скриптов в $DEST"
mkdir -p "$DEST" "$STATE"
cp "$HERE"/hooks/*.sh "$DEST"/
chmod +x "$DEST"/*.sh
echo "  ✓ $(ls "$HERE"/hooks/*.sh | wc -l) скриптов"

echo "==> Регистрация хуков в $SETTINGS"
python3 - "$SETTINGS" "$DEST" <<'PY'
import json, os, sys, shutil
settings_path, hooks_dir = sys.argv[1], sys.argv[2]
try:
    with open(settings_path, encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception as e:
    print("  ✗ settings.json не парсится, правка отменена:", e); sys.exit(1)

mapping = {
    "Notification":      "notify-linux.sh",    # idle/permission (терминал-режим)
    "PermissionRequest": "notify-linux.sh",    # запрос разрешения (работает в native UI)
    "PreToolUse":        "notify-pretool.sh",  # запоминает запрашиваемую команду
    "UserPromptSubmit":  "notify-clear.sh",    # гасит повторы + старт хода
    "PostToolUse":       "notify-clear.sh",    # гасит повторы (работа возобновилась)
    "Stop":              "notify-stop.sh",     # баннер "готово" после долгого хода
}
hooks = data.setdefault("hooks", {})
added = 0
for event, script in mapping.items():
    cmd = os.path.join(hooks_dir, script)
    groups = hooks.setdefault(event, [])
    already = any(h.get("command", "").endswith(script)
                  for g in groups for h in g.get("hooks", []))
    if already:
        continue
    groups.append({"matcher": "", "hooks": [
        {"type": "command", "command": cmd, "timeout": 15}]})
    added += 1

if os.path.exists(settings_path):
    shutil.copy(settings_path, settings_path + ".bak-notif")
with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f"  ✓ добавлено хуков: {added} (уже стоявшие пропущены)")
if os.path.exists(settings_path + ".bak-notif"):
    print(f"  ✓ бэкап: {settings_path}.bak-notif")
PY

cat <<'EOF'

ГОТОВО.
⚠  ПОЛНОСТЬЮ перезапусти VSCode (закрой окно и открой заново).
   Хуки читаются на старте сессии; правки в живой сессии Claude Code
   затирает своим автосейвом разрешений — без рестарта не сработает.

Проверка: дай Claude команду, требующую подтверждения — должен всплыть
KDE-баннер с именем чата в заголовке. Сам уходит через ~5с, повторяется
раз в минуту, пока не отреагируешь.

Звук по умолчанию ВЫКЛЮЧЕН. Включить всегда-со-звуком: добавь в "env"
файла ~/.claude/settings.json строку  "CC_SOUND": "1".
EOF
