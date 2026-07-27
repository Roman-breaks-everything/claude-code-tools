#!/usr/bin/env bash
# _reminder.sh <noncefile> <nonce> <idfile> <title> <msg>
# Detached background loop: every $CC_NOTIFY_INTERVAL seconds re-show the banner
# while the "pending" marker still holds OUR nonce. Stops when:
#   - the marker file is gone        (user reacted -> notify-clear.sh removed it)
#   - the marker holds a new nonce    (a newer notification superseded us)
#   - the reminder cap is reached     ($CC_NOTIFY_MAX)
# Each re-show reuses <idfile> so _notify.sh refreshes the single banner.
noncefile="$1"; nonce="$2"; idfile="$3"; title="$4"; msg="$5"
interval="${CC_NOTIFY_INTERVAL:-60}"
max="${CC_NOTIFY_MAX:-20}"
notify="$(dirname "$0")/_notify.sh"

i=0
while [ "$i" -lt "$max" ]; do
  sleep "$interval"
  [ "$(cat "$noncefile" 2>/dev/null)" = "$nonce" ] || exit 0
  i=$((i + 1))
  "$notify" "$idfile" "$title" "‼️ ожидается действие (напоминание #$i): $msg"
done
# Gave up after $max reminders — drop our marker so a future hook starts clean.
[ "$(cat "$noncefile" 2>/dev/null)" = "$nonce" ] && rm -f "$noncefile" 2>/dev/null
exit 0
