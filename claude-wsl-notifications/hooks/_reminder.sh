#!/usr/bin/env bash
# _reminder.sh <noncefile> <nonce> <title> <msg> [<launch-uri>]
# Detached background loop: every $CC_NOTIFY_INTERVAL seconds re-shows the toast
# while the "pending" marker still holds OUR nonce. Stops when:
#   - the marker file is gone        (user reacted -> notify-clear.sh removed it)
#   - the marker holds a new nonce    (a newer notification superseded us)
#   - the reminder cap is reached     ($CC_NOTIFY_MAX)
noncefile="$1"; nonce="$2"; title="$3"; msg="$4"; launch="${5:-}"
interval="${CC_NOTIFY_INTERVAL:-60}"
max="${CC_NOTIFY_MAX:-20}"
toast="$(dirname "$0")/_toast.sh"

i=0
while [ "$i" -lt "$max" ]; do
  sleep "$interval"
  [ "$(cat "$noncefile" 2>/dev/null)" = "$nonce" ] || exit 0
  i=$((i + 1))
  "$toast" "$title" "‼️ ожидается действие (напоминание #$i): $msg" "$launch"
done
# Gave up after $max reminders — drop our marker so a future hook starts clean.
[ "$(cat "$noncefile" 2>/dev/null)" = "$nonce" ] && rm -f "$noncefile" 2>/dev/null
exit 0
