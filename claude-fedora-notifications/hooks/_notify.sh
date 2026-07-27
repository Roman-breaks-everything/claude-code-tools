#!/usr/bin/env bash
# _notify.sh <idfile> <title> <body>
# Show one native KDE/Plasma notification on Fedora by calling the freedesktop
# notification service DIRECTLY over D-Bus (gdbus). We bypass libnotify's portal
# path on purpose: inside the VSCode Flatpak sandbox the portal swallows the
# urgency/expire hints and dumps everything straight into the notification
# history instead of popping a banner. The direct Notify call pops correctly.
#
# Behaviour:
#   * urgency = normal, expire = $CC_NOTIFY_EXPIRE ms (default 5000) -> the banner
#     pops, then auto-dismisses; the every-minute reminder loop re-pops it.
#   * sound OFF by default. CC_SOUND=1 attaches a sound-name hint (always plays).
#     "only when VSCode is not focused" is impossible here: org.kde.KWin is not
#     exposed on the sandbox bus and Wayland forbids active-window queries.
#   * <idfile> (optional): the returned notification id is stored there. On the
#     next call we first CloseNotification(old id), then post the new one, so
#     reminders keep exactly ONE banner / one history entry instead of stacking.
#     (Plasma 6 ignores replaces_id for an already-shown/expired id and pops a
#     duplicate, so an explicit close is the reliable way.) Pass "" to skip this.

idfile="${1:-}"
title="${2:-Claude Code}"
body="${3:-Нужно ваше действие}"

CC_T="$title" CC_B="$body" CC_IDFILE="$idfile" python3 - <<'PY'
import os, re, subprocess

title  = os.environ.get("CC_T", "Claude Code")
body   = os.environ.get("CC_B", "Нужно ваше действие")
idfile = os.environ.get("CC_IDFILE", "").strip()
expire = os.environ.get("CC_NOTIFY_EXPIRE", "5000").strip() or "5000"
sound  = os.environ.get("CC_SOUND", "0").strip() not in ("", "0", "false", "no")

try:
    expire_i = int(expire)
except ValueError:
    expire_i = 5000

def gv(s):  # GVariant string literal: escape backslash and double-quote
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

NOTIF = ["gdbus", "call", "--session",
         "--dest", "org.freedesktop.Notifications",
         "--object-path", "/org/freedesktop/Notifications",
         "--method"]

# Close the previously shown banner first (Plasma ignores replaces_id once a
# notification has been shown/expired and would pop a duplicate otherwise).
if idfile:
    old = 0
    try:
        with open(idfile) as f:
            old = int(re.sub(r"\D", "", f.read()) or "0")
    except Exception:
        old = 0
    if old:
        try:
            subprocess.run(NOTIF + ["org.freedesktop.Notifications.CloseNotification", str(old)],
                           capture_output=True, text=True, timeout=10)
        except Exception:
            pass

# urgency byte 1 = normal. Sound is opt-in via CC_SOUND.
hints = "{'urgency': <byte 1>"
if sound:
    hints += ", 'sound-name': <'message-new-instant'>"
hints += "}"

argv = NOTIF + [
    "org.freedesktop.Notifications.Notify",
    gv("Claude Code"),      # app_name (cosmetic; KDE shows the summary as title)
    "0",                    # replaces_id (we close the old one explicitly above)
    gv(""),                 # app_icon
    gv(title[:120]),        # summary  -> banner TITLE (chat name)
    gv(body[:300]),         # body
    "[]",                   # actions
    hints,                  # hints
    str(expire_i),          # expire_timeout (ms); -1 = server default, 0 = never
]

try:
    out = subprocess.run(argv, capture_output=True, text=True, timeout=10).stdout
except Exception:
    out = ""

# Parse "(uint32 NN,)" and remember the id for in-place replacement next time.
if idfile:
    m = re.search(r"uint32\s+(\d+)", out)
    if m:
        try:
            with open(idfile, "w") as f:
                f.write(m.group(1))
        except Exception:
            pass
PY
exit 0
