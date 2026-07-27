#!/usr/bin/env bash
# Claude Code `Notification` hook -> Windows toast (WSL2) + repeat reminders.
# Shows a toast immediately, then keeps reminding every minute until the user
# reacts (UserPromptSubmit / PostToolUse -> notify-clear.sh wipes the marker).

HOOKDIR="$(dirname "$0")"
STATE="$HOME/.claude/notify-state"
mkdir -p "$STATE"

payload="$(cat)"
# Keep the last raw payload for diagnostics (lets us see the real field names).
printf '%s\n' "$payload" > "$STATE/last-payload.json" 2>/dev/null

# Parse fields safely into shell vars (shlex-quoted) and eval.
# Payload goes via env, NOT stdin: the heredoc already occupies python's stdin.
eval "$(CC_PAYLOAD="$payload" python3 - <<'PY'
import os, re, json, shlex
try:
    d = json.loads(os.environ.get("CC_PAYLOAD") or "{}")
except Exception:
    d = {}
sid   = d.get("session_id") or "default"
safe  = re.sub(r"[^A-Za-z0-9_-]", "_", sid)
evt   = d.get("hook_event_name") or ""
ntype = d.get("notification_type") or ""
msg   = (d.get("message") or "").strip()
cwd   = d.get("cwd") or ""
proj  = cwd.rstrip("/").split("/")[-1] if cwd else ""

# Chat title (the tab name Claude Code auto-generates) lives in the transcript
# as the last `ai-title` record -> use it so multi-chat toasts are tellable apart.
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
title = chosen[:64] if chosen else ("Claude Code" + (" — " + proj if proj else ""))

# Build the requested action from THIS payload (PermissionRequest carries
# tool_name + tool_input directly), falling back to the file written by
# notify-pretool.sh on PreToolUse.
def summarize(tool, ti):
    if not tool:
        return ""
    if tool == "Bash":
        return "Bash · " + (ti.get("command") or "")
    if tool in ("Edit", "Write", "NotebookEdit", "Read"):
        return tool + " · " + os.path.basename(ti.get("file_path") or "")
    if tool.startswith("mcp__"):
        return "MCP · " + tool.split("__")[-1]
    return tool

action = " ".join(summarize(d.get("tool_name") or "", d.get("tool_input") or {}).split())[:140]
if not action:
    try:
        with open(os.path.join(os.path.expanduser("~/.claude/notify-state"), safe + ".action")) as f:
            action = f.read().strip()
    except Exception:
        pass

if evt == "PermissionRequest" or ntype == "permission_prompt":
    body = "❓ Разрешить — " + (action or msg or "запрос инструмента")
elif ntype == "idle_prompt":
    body = "💬 Claude ждёт твоего ответа"
elif ntype.startswith("elicitation"):
    body = "📝 " + (msg or "Нужен ввод (MCP-форма)")
else:
    body = msg or action or "Нужно ваше действие"

# Click target: open this exact chat in VSCode via the extension's uri handler.
# Optional override: notify-state/launch.tmpl (must contain {SID}); default below.
tmpl = "vscode://anthropic.claude-code/open?session={SID}"
try:
    with open(os.path.join(os.path.expanduser("~/.claude/notify-state"), "launch.tmpl")) as f:
        t = f.read().strip()
        if t:
            tmpl = t
except Exception:
    pass
launch = tmpl.replace("{SID}", sid)

print("CC_SID=" + shlex.quote(sid))
print("CC_TITLE=" + shlex.quote(title))
print("CC_MSG=" + shlex.quote(body))
print("CC_LAUNCH=" + shlex.quote(launch))
PY
)"

# 1) immediate toast (clicking it opens this chat in VSCode)
"$HOOKDIR/_toast.sh" "$CC_TITLE" "$CC_MSG" "$CC_LAUNCH"

# 2) arm the "pending" marker (a fresh nonce invalidates any older loop)
nonce="${RANDOM}-$$-$(date +%s)"
noncefile="$STATE/$(printf '%s' "$CC_SID" | tr -c 'A-Za-z0-9_-' '_').nonce"
printf '%s' "$nonce" > "$noncefile"

# 3) detached reminder loop — setsid so Claude's hook timeout can't kill it
setsid bash "$HOOKDIR/_reminder.sh" "$noncefile" "$nonce" "$CC_TITLE" "$CC_MSG" "$CC_LAUNCH" \
  </dev/null >/dev/null 2>&1 &
disown 2>/dev/null

exit 0
