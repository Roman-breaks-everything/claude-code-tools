#!/usr/bin/env bash
# PreToolUse hook: records WHAT action Claude is about to request into
# <sid>.action, so the Notification(permission_prompt) toast can show the
# actual command / file instead of a generic "tool requires permission".
# PreToolUse fires BEFORE the permission prompt, so this file is fresh.
STATE="$HOME/.claude/notify-state"
mkdir -p "$STATE"
payload="$(cat)"

CC_PAYLOAD="$payload" python3 - <<'PY'
import os, re, json
try:
    d = json.loads(os.environ.get("CC_PAYLOAD") or "{}")
except Exception:
    d = {}

sid  = d.get("session_id") or "default"
safe = re.sub(r"[^A-Za-z0-9_-]", "_", sid)
tool = d.get("tool_name") or "?"
ti   = d.get("tool_input") or {}

if tool == "Bash":
    s = "Bash · " + (ti.get("command") or "")
elif tool in ("Edit", "Write", "NotebookEdit", "Read"):
    s = tool + " · " + os.path.basename(ti.get("file_path") or "")
elif tool.startswith("mcp__"):
    s = "MCP · " + tool.split("__")[-1]
else:
    s = tool

s = " ".join(s.split())[:140]
state = os.path.expanduser("~/.claude/notify-state")
try:
    with open(os.path.join(state, safe + ".action"), "w") as f:
        f.write(s)
except Exception:
    pass
PY
exit 0
