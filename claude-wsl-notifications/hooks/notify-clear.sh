#!/usr/bin/env bash
# Stops the reminder loop for the current session by removing the marker.
# Bound to UserPromptSubmit (user typed) and PostToolUse (work resumed).
# On UserPromptSubmit it ALSO stamps the turn-start time (used by notify-stop.sh
# to decide whether a turn was "long") and clears any stale pending action.
STATE="$HOME/.claude/notify-state"
mkdir -p "$STATE"
payload="$(cat)"

eval "$(CC_PAYLOAD="$payload" python3 - <<'PY'
import os, re, json, shlex
try:
    d = json.loads(os.environ.get("CC_PAYLOAD") or "{}")
except Exception:
    d = {}
sid  = d.get("session_id") or "default"
safe = re.sub(r"[^A-Za-z0-9_-]", "_", sid)
evt  = d.get("hook_event_name") or ""
print("CC_SAFE=" + shlex.quote(safe))
print("CC_EVT=" + shlex.quote(evt))
PY
)"

rm -f "$STATE/$CC_SAFE.nonce" 2>/dev/null

if [ "$CC_EVT" = "UserPromptSubmit" ]; then
  date +%s > "$STATE/$CC_SAFE.turnstart" 2>/dev/null
  rm -f "$STATE/$CC_SAFE.action" 2>/dev/null
fi
exit 0
