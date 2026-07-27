#!/usr/bin/env bash
# Дашборд контекста ТОЛЬКО по ОТКРЫТЫМ чатам в ОДНОЙ панели. Запусти один раз в
# интегрированном терминале VSCode (split) — увидишь строку на каждый открытый
# чат со временем, именем, баром заполнения контекста и токенами. Раз в секунду
# обновляется. Ctrl+C — выход.
#
#   › refactor auth module           ▓▓░░░░░░░░  23% · 232k/1M
#     update API docs                ▓▓░░░░░░░░  20% · 197k/1M
#
# «Открытый чат» определяется по живым процессам: расширение VSCode держит по
# процессу `claude` на каждую открытую вкладку. Возобновлённый чат несёт в
# аргументах `--resume <session-id>` → точный id транскрипта. Новый чат (ещё не
# закрывавшийся) стартует без --resume и свой id наружу не отдаёт — поэтому его
# транскрипт сопоставляется по времени: first-event транскрипта должен лежать во
# «владении» не-resume процесса (start процесса ≤ first-event, каждый процесс
# берёт один транскрипт). Так закрытые чаты и пустые вкладки без истории
# отсекаются. Каждый тик перечитываем /proc → открытие/закрытие видно на лету.
#
# Один процесс python с кэшем: перечитывает только те транскрипты, чей mtime
# изменился, поэтому дёшев даже при многих чатах. Кросс-платформенно (WSL/Fedora).
#
# Настройки (env):
#   CC_WATCH_INTERVAL  период обновления, сек (1)
#   CC_DASH_MAX        максимум строк-чатов (8)
#   CC_CTX_LIMIT       лимит окна вручную (иначе авто: …[1m]→1M, иначе 200k)

exec python3 - <<'PY'
import os, glob, json, time, sys, signal, re, datetime

BASE     = os.path.expanduser("~/.claude/projects")
INTERVAL = float(os.environ.get("CC_WATCH_INTERVAL", "1") or 1)
MAX_ROWS = int(os.environ.get("CC_DASH_MAX", "8") or 8)
NAMEW    = 24
WIDTH    = 10

NC, DIM, CYAN, BOLD = "\033[0m", "\033[2m", "\033[36m", "\033[1m"

def restore(*_):
    sys.stdout.write("\033[?25h\n"); sys.stdout.flush(); sys.exit(0)
signal.signal(signal.SIGTERM, restore)
signal.signal(signal.SIGINT, restore)

cache = {}   # path -> (mtime, title, ctx, model_id)

def compute(fp):
    ai = cu = ""; ctx = 0; model = ""
    try:
        with open(fp, encoding="utf-8") as f:
            for line in f:
                if ('"usage"' not in line and '"model"' not in line
                        and '"aiTitle"' not in line and '"customTitle"' not in line):
                    continue
                try: o = json.loads(line)
                except Exception: continue
                if o.get("type") == "custom-title" and o.get("customTitle"): cu = o["customTitle"]
                elif o.get("type") == "ai-title" and o.get("aiTitle"):       ai = o["aiTitle"]
                m = o.get("message") or {}
                if m.get("role") != "assistant": continue
                if m.get("model"): model = str(m["model"]).lower()
                u = m.get("usage") or {}
                if u:
                    ctx = (u.get("input_tokens", 0)
                           + u.get("cache_read_input_tokens", 0)
                           + u.get("cache_creation_input_tokens", 0))
    except Exception:
        pass
    return (cu or ai or "—"), ctx, model

def live_claude_procs():
    """(resumed_ids, nonres_starts): по живому процессу claude на открытую
    вкладку. resumed_ids — id из --resume (точные). nonres_starts —
    отсортированные epoch-времена старта вкладок без --resume (новые чаты)."""
    try:
        hz = os.sysconf("SC_CLK_TCK")
        btime = next(int(l.split()[1]) for l in open("/proc/stat") if l.startswith("btime"))
    except Exception:
        hz, btime = 100, 0
    resumed, starts = set(), []
    for d in glob.glob("/proc/[0-9]*"):
        try:
            parts = open(d + "/cmdline", "rb").read().split(b"\x00")
        except Exception:
            continue
        if not any(b"native-binary/claude" in p for p in parts):
            continue
        # Только реальные вкладки чата несут --replay-user-messages. Хелперы
        # (--claude-in-chrome-mcp и пр.) тоже запускаются из native-binary/claude,
        # но вкладками не являются — иначе они дают фантомные слоты под "новый чат"
        # и жадный матчер показывает закрытые чаты как открытые.
        if not any(p == b"--replay-user-messages" for p in parts):
            continue
        rid = None
        for i, p in enumerate(parts):
            if p == b"--resume" and i + 1 < len(parts):
                rid = parts[i + 1].decode("utf-8", "replace"); break
            if p.startswith(b"--resume="):
                rid = p[len(b"--resume="):].decode("utf-8", "replace"); break
        if rid:
            resumed.add(rid)
        else:
            try:
                raw = open(d + "/stat", "rb").read()
                after = raw[raw.rfind(b")") + 2:].split()      # после "(comm) "
                starts.append(btime + int(after[19]) / hz)     # поле 22 = starttime
            except Exception:
                pass
    starts.sort()
    return resumed, starts

_first_ev = {}   # path -> first-event epoch (стабилен, кэшируем навсегда)
def first_event(fp):
    if fp in _first_ev:
        return _first_ev[fp]
    ep = None
    try:
        with open(fp, encoding="utf-8") as f:
            for line in f:
                try: o = json.loads(line)
                except Exception: continue
                ts = o.get("timestamp")
                if ts:
                    ep = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
                    break
    except Exception:
        pass
    _first_ev[fp] = ep
    return ep

def match_new_chats(files, resumed, nonres_starts):
    """Жадно сопоставляем не-resume транскрипты живым не-resume процессам по
    времени: транскрипт T открыт, если есть незанятый процесс со start ≤
    first_event(T). files = [(fp, mt, sid), ...]. mt ≥ first_event, поэтому
    транскрипты с mt < самого раннего старта отсеиваем без чтения файла."""
    if not nonres_starts:
        return set()
    min_start = nonres_starts[0]
    cands = []
    for fp, mt, sid in files:
        if sid in resumed or mt < min_start:
            continue
        fe = first_event(fp)
        if fe is not None:
            cands.append((fe, sid))
    cands.sort()
    used = [False] * len(nonres_starts)
    new_open = set()
    for fe, sid in cands:
        for k, st in enumerate(nonres_starts):     # старты по возрастанию
            if not used[k] and st <= fe:
                used[k] = True; new_open.add(sid); break
    return new_open

def read_settings():
    """Глобальные model + effortLevel из settings.json (читаем каждый тик —
    файл крошечный, зато effort/режим подхватываются на лету)."""
    try:
        with open(os.path.expanduser("~/.claude/settings.json")) as sf:
            d = json.load(sf)
            return str(d.get("model", "") or ""), str(d.get("effortLevel", "") or "")
    except Exception:
        return "", ""

def limit_for(model, settings_model):
    env = os.environ.get("CC_CTX_LIMIT", "").strip()
    if env.isdigit(): return int(env)
    one_m = "1m" in model or "1m" in settings_model.lower()
    return 1_000_000 if one_m else 200_000

def short_model(mid):
    s = re.sub(r"-\d{6,}$", "", mid.replace("claude-", ""))  # убрать дату-суффикс
    s = re.sub(r"(\d)-(\d)", r"\1.\2", s)                    # opus-4-8 -> opus-4.8
    return s or "—"

def human(n):
    if n >= 1_000_000: return f"{n/1_000_000:.1f}M".replace(".0M", "M")
    if n >= 1_000:     return f"{round(n/1000)}k"
    return str(n)

def color(p):
    return "\033[32m" if p < 50 else ("\033[33m" if p < 80 else "\033[31m")

sys.stdout.write("\033[?25l")  # спрятать курсор
try:
    while True:
        files = []
        for fp in glob.glob(os.path.join(BASE, "*", "*.jsonl")):
            try: mt = os.path.getmtime(fp)
            except OSError: continue
            files.append((fp, mt, os.path.basename(fp)[:-6]))  # [:-6] = убрать ".jsonl"

        resumed, nonres_starts = live_claude_procs()
        open_ids = resumed | match_new_chats(files, resumed, nonres_starts)

        rows = []
        for fp, mt, sid in files:
            if sid not in open_ids:
                continue
            c = cache.get(fp)
            if not c or c[0] != mt:
                title, ctx, model = compute(fp)
                cache[fp] = (mt, title, ctx, model)
            else:
                _, title, ctx, model = c
            rows.append((mt, title, ctx, model))
        rows.sort(key=lambda r: r[0], reverse=True)
        rows = rows[:MAX_ROWS]

        s_model, s_effort = read_settings()   # effort — глобальный, один на все чаты

        out = ["\033[H\033[J"]  # домой + очистить экран (без шапки)
        if not rows:
            out.append(f"{DIM}нет открытых чатов{NC}")
        for i, (mt, title, ctx, model) in enumerate(rows):
            lim = limit_for(model, s_model)
            pct = 0 if lim <= 0 else min(100, round(ctx * 100 / lim))
            filled = 0 if lim <= 0 else min(WIDTH, round(ctx * WIDTH / lim))
            bar = "▓" * filled + "░" * (WIDTH - filled)
            name = title[:NAMEW].ljust(NAMEW)
            mdl = short_model(model)[:11].ljust(11)
            eff = (s_effort or "—")[:7].ljust(7)
            mark = "›" if i == 0 else " "
            out.append(f"{DIM}{mark}{NC} {BOLD}{name}{NC} "
                       f"{DIM}model:{NC} {mdl} {DIM}effort:{NC} {eff} "
                       f"{DIM}context:{NC} {color(pct)}{bar} {pct:3d}%{NC} "
                       f"{DIM}· {human(ctx)}/{human(lim)}{NC}")
        sys.stdout.write("\n".join(out) + "\n")
        sys.stdout.flush()
        time.sleep(INTERVAL)
except KeyboardInterrupt:
    restore()
PY
