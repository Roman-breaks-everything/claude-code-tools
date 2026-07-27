#!/usr/bin/env bash
# _toast.sh "<title>" "<body>" ["<launch-uri>"] — show one native Windows toast (WSL2).
# Unique Tag per call so Windows never silently replaces a previous toast.
# Sound: SILENT when the focused window is VSCode (you're already looking),
# WITH SOUND otherwise. Detected foreground name -> notify-state/last-fg.txt.
# If <launch-uri> is given, clicking the toast opens it (activationType=protocol),
# e.g. vscode://anthropic.claude-code/open?session=<id> to jump to that chat.

title="${1:-Claude Code}"
body="${2:-Нужно ваше действие}"
launch="${3:-}"
uid="cc-${RANDOM}$(date +%s | tail -c 7)"
STATE="$HOME/.claude/notify-state"

enc="$(CC_T="$title" CC_B="$body" CC_UID="$uid" CC_LAUNCH="$launch" python3 - <<'PY'
import os, base64

def q(s):  # escape for a PowerShell single-quoted string
    return s.replace("'", "''")

title  = q(os.environ.get("CC_T", "Claude Code"))
body   = q(os.environ.get("CC_B", "Нужно ваше действие"))
uid    = q((os.environ.get("CC_UID") or "cc")[:16])
launch = q(os.environ.get("CC_LAUNCH", "").strip())

launchset = ""
if launch:
    launchset = ("$t.DocumentElement.SetAttribute('launch','" + launch + "')|Out-Null;"
                 "$t.DocumentElement.SetAttribute('activationType','protocol')|Out-Null;")

ps = r'''Add-Type 'using System;using System.Runtime.InteropServices;public class FG{[DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();[DllImport("user32.dll")]public static extern int GetWindowThreadProcessId(IntPtr h,out int p);}';
$h=[FG]::GetForegroundWindow();$p=0;[void][FG]::GetWindowThreadProcessId($h,[ref]$p);
$fg='';try{$fg=(Get-Process -Id $p -ErrorAction Stop).Name}catch{};
$focused=@('Code','Code - Insiders') -contains $fg;
[void][Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime];
$t=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);
$x=$t.GetElementsByTagName('text');
$x.Item(0).AppendChild($t.CreateTextNode('__TITLE__'))|Out-Null;
$x.Item(1).AppendChild($t.CreateTextNode('__BODY__'))|Out-Null;
__LAUNCHSET__
if($focused){$au=$t.CreateElement('audio');$au.SetAttribute('silent','true');$t.DocumentElement.AppendChild($au)|Out-Null;}
$n=[Windows.UI.Notifications.ToastNotification]::new($t);
$n.Tag='__UID__';$n.Group='ClaudeCode';
$a='{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe';
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($a).Show($n);
Write-Output $fg;'''
ps = (ps.replace('__TITLE__', title).replace('__BODY__', body)
        .replace('__UID__', uid).replace('__LAUNCHSET__', launchset))
print(base64.b64encode(ps.encode('utf-16-le')).decode())
PY
)"

if [ -n "$enc" ]; then
  fg="$(powershell.exe -NoProfile -NonInteractive -EncodedCommand "$enc" 2>/dev/null | tr -d '\r\n')"
  printf '%s' "$fg" > "$STATE/last-fg.txt" 2>/dev/null
fi
exit 0
