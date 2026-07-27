#!/usr/bin/env bash
# Установщик дашборда открытых чатов Claude Code (context + токены, БЕЗ часов).
# Копирует dash-statusline.sh в ~/.claude/hooks/ и снимает старую "часовую"
# statusLine, если она осталась от прежней версии. Идемпотентно. WSL / Fedora.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

echo "==> Проверка окружения"
command -v python3 >/dev/null 2>&1 || { echo "  ✗ python3 не найден"; exit 1; }
echo "  ✓ python3"

echo "==> Копирование дашборда в $DEST"
mkdir -p "$DEST"
cp "$HERE/dash-statusline.sh" "$DEST/dash-statusline.sh"
chmod +x "$DEST/dash-statusline.sh"
echo "  ✓ $DEST/dash-statusline.sh"

echo "==> Удаление старой версии с часами (если была)"
for old in statusline.sh watch-statusline.sh; do
  if [ -e "$DEST/$old" ]; then rm -f "$DEST/$old"; echo "  ✓ удалён $DEST/$old"; fi
done

# Снять statusLine из settings.json, только если она указывает на наш statusline.sh (часы).
python3 - "$SETTINGS" <<'PY'
import json, os, sys, shutil
p = sys.argv[1]
try:
    with open(p, encoding="utf-8") as f: data = json.load(f)
except FileNotFoundError:
    sys.exit(0)
except Exception as e:
    print("  ! settings.json не парсится, чистку statusLine пропускаю:", e); sys.exit(0)
sl = data.get("statusLine")
if isinstance(sl, dict) and os.path.basename(str(sl.get("command", ""))) == "statusline.sh":
    shutil.copy(p, p + ".bak-statusline")
    data.pop("statusLine", None)
    with open(p, "w", encoding="utf-8") as f: json.dump(data, f, indent=2, ensure_ascii=False)
    print("  ✓ снята старая statusLine с часами (бэкап .bak-statusline)")
PY

cat <<EOF

ГОТОВО. Остался только дашборд (без часов). Запуск в терминале VSCode (split):

    $DEST/dash-statusline.sh

Строка на КАЖДЫЙ открытый чат: имя, model, effort, бар контекста, токены.
Обновление раз в секунду, Ctrl+C — выход.

Настройка (env): CC_CTX_LIMIT=<число> — лимит окна вручную;
                 CC_WATCH_INTERVAL=<сек> — период обновления (по умолч. 1);
                 CC_DASH_MAX=<число> — максимум строк-чатов (8).
EOF
