#!/usr/bin/env bash
# Stop hook: Claude finished its turn (handed control back to you).
# Fires a "done" banner ONLY if the turn took >= CC_DONE_MIN_SECONDS (default 45),
# so quick back-and-forth while you're watching stays silent, but long tasks
# (where you likely stepped away) notify you. Also clears any pending marker.
HOOKDIR="$(dirname "$0")"
STATE="$HOME/.claude/notify-state"
mkdir -p "$STATE"
min="${CC_DONE_MIN_SECONDS:-45}"
payload="$(cat)"

eval "$(CC_PAYLOAD="$payload" python3 - <<'PY'
import os, re, json, shlex
try:
    d = json.loads(os.environ.get("CC_PAYLOAD") or "{}")
except Exception:
    d = {}
sid  = d.get("session_id") or "default"
safe = re.sub(r"[^A-Za-z0-9_-]", "_", sid)
cwd  = d.get("cwd") or ""
proj = cwd.rstrip("/").split("/")[-1] if cwd else ""
ai_title = ""
custom_title = ""
tp = d.get("transcript_path") or ""
try:
    with open(tp, encoding="utf-8") as f:
        for line in f:
            if '"customTitle"' in line and '"custom-title"' in line:
                try:
                    o = json.loads(line)
                    if o.get("type") == "custom-title" and o.get("customTitle"):
                        custom_title = o["customTitle"]
                except Exception:
                    pass
            elif '"aiTitle"' in line and '"ai-title"' in line:
                try:
                    o = json.loads(line)
                    if o.get("type") == "ai-title" and o.get("aiTitle"):
                        ai_title = o["aiTitle"]
                except Exception:
                    pass
except Exception:
    pass
chosen = custom_title or ai_title  # ручное переименование важнее авто-названия
title = chosen[:120] if chosen else ("Claude Code" + (" — " + proj if proj else ""))
active = "1" if d.get("stop_hook_active") else "0"
print("CC_SAFE=" + shlex.quote(safe))
print("CC_TITLE=" + shlex.quote(title))
print("CC_STOP_ACTIVE=" + shlex.quote(active))
PY
)"

# Avoid the re-entrant Stop loop (we never block, but stay safe).
[ "$CC_STOP_ACTIVE" = "1" ] && exit 0

# Turn is over -> stop reminders and forget the pending action.
rm -f "$STATE/$CC_SAFE.nonce" "$STATE/$CC_SAFE.action" 2>/dev/null
# Close any lingering pending banner and reset its id file.
idfile="$STATE/$CC_SAFE.nid"
if [ -f "$idfile" ]; then
  old="$(tr -dc '0-9' < "$idfile" 2>/dev/null)"
  [ -n "$old" ] && gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$old" >/dev/null 2>&1
  rm -f "$idfile" 2>/dev/null
fi

# Duration since the turn started (written by notify-clear.sh on UserPromptSubmit).
startf="$STATE/$CC_SAFE.turnstart"
now="$(date +%s)"
start="$(cat "$startf" 2>/dev/null)"
rm -f "$startf" 2>/dev/null

case "$start" in (*[!0-9]*|"") exit 0 ;; esac   # no valid start -> skip banner
elapsed=$((now - start))
[ "$elapsed" -lt "$min" ] && exit 0             # quick turn -> stay silent

mm=$((elapsed / 60)); ss=$((elapsed % 60))
[ "$mm" -gt 0 ] && dur="${mm}м ${ss}с" || dur="${ss}с"
# Done banner is one-shot: no idfile, so it won't be replaced/closed by reminders.
"$HOOKDIR/_notify.sh" "" "$CC_TITLE" "✅ Готово — Claude закончил (за ${dur})"
exit 0
