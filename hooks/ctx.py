"""Контекст и кеш: строка состояния, страж возврата после паузы, подхват handoff после /clear.

python ctx.py status   строка состояния (stdin — JSON строки состояния Claude Code)
python ctx.py guard    хук UserPromptSubmit: остывший кеш + большой контекст → предупредить один раз
python ctx.py start    хук SessionStart: после /clear подложить свежий .claude/work/handoff.md
Данные только читаются; модель не вызывается. Любая ошибка — молча выйти, работу не ломать.
"""
import json, os, sys, time
from datetime import datetime

GUARD_MIN_CTX = 100_000      # меньше — перезапись после паузы дешёвая, не мешать
GUARD_PAUSE_MIN = 60         # TTL кеша подписки — 1 час
GUARD_BYPASS_MIN = 10        # повторная отправка в течение этого времени проходит без проверки
WARN_CTX = 300_000           # выше — сжатие базы должно было сработать
HANDOFF = os.path.join(".claude", "work", "handoff.md")
HANDOFF_FULL_H = 2       # /clear вскоре после /handoff — подложить файл целиком
HANDOFF_FRESH_H = 24     # позже — только строку-указатель
PRICE_IN = {"opus": 4.0, "sonnet": 2.0, "haiku": 1.0, "fable": 10.0}   # $/1M вход; запись в 1ч-кеш = 2×
STATE = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"), "claude-base-state")


def k(n):
    return f"{n / 1e6:.1f}M" if n >= 1e6 else f"{n / 1e3:.0f}k"


def ctx_of(u):
    return sum(u.get(x) or 0 for x in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))


def last_turn(path):
    """(контекст, время, модель) последнего ответа API — из хвоста транскрипта."""
    with open(path, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - 4_000_000))
        lines = f.read().decode("utf-8", "ignore").splitlines()
    for line in reversed(lines):
        if '"usage"' not in line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        m = d.get("message") or {}
        if (d.get("type") == "assistant" and ctx_of(m.get("usage") or {}) and d.get("timestamp")
                and not (m.get("model") or "").startswith("<")):   # <synthetic>: прерывание, ошибка API
            t = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00")).timestamp()
            return ctx_of(m["usage"]), t, m.get("model") or ""
    return 0, None, ""


def pct(v):
    """Процент из блока лимита, как бы он ни назывался."""
    if isinstance(v, (int, float)):
        return v
    if isinstance(v, dict):
        for key, x in v.items():
            if isinstance(x, (int, float)) and ("percent" in key or "util" in key):
                return x * 100 if x <= 1 and "util" in key else x
    return None


def status(d):
    parts = [(d.get("model") or {}).get("display_name", "")]
    cw = d.get("context_window") or {}
    ctx = ctx_of(cw.get("current_usage") or {})
    if not ctx and d.get("transcript_path"):
        ctx = last_turn(d["transcript_path"])[0]
    if ctx:
        parts.append(f"контекст {k(ctx)}" + (" ⚠" if ctx > WARN_CTX else ""))
    pc = d.get("prompt_cache") or {}
    exp = pc.get("expires_at")
    if isinstance(exp, str):
        try:
            exp = datetime.fromisoformat(exp.replace("Z", "+00:00")).timestamp()
        except ValueError:
            exp = None
    if isinstance(exp, (int, float)) and exp > 1e12:
        exp /= 1000
    if pc.get("warm") and isinstance(exp, (int, float)) and exp > time.time():
        parts.append(f"кеш ещё {int((exp - time.time()) // 60)} мин")
    elif pc.get("warm") is False and ctx > GUARD_MIN_CTX:
        parts.append("кеш остыл: /handoff и /clear дешевле")
    rl = d.get("rate_limits") or {}
    for key, name in (("five_hour", "5ч"), ("seven_day", "неделя")):
        p = pct(rl.get(key))
        if p is not None:
            parts.append(f"{name} {p:.0f}%")
    print(" · ".join(p for p in parts if p))


def guard(d):
    prompt = (d.get("prompt") or "").strip()
    if prompt.startswith("/") or not d.get("transcript_path"):
        return
    ctx, t, model = last_turn(d["transcript_path"])
    if t is None:
        return
    pause = (time.time() - t) / 60
    if pause < GUARD_PAUSE_MIN or ctx < GUARD_MIN_CTX:
        return
    os.makedirs(STATE, exist_ok=True)
    mark = os.path.join(STATE, "guard-" + "".join(c for c in d.get("session_id", "x") if c.isalnum() or c == "-"))
    if os.path.exists(mark) and time.time() - os.path.getmtime(mark) < GUARD_BYPASS_MIN * 60:
        os.remove(mark)
        return
    open(mark, "w").close()
    p = next((v for n, v in PRICE_IN.items() if n in model), 2.0)
    reason = (f"Пауза {pause:.0f} мин — кеш остыл. Этот запрос заново запишет весь контекст: {k(ctx)} токенов "
              f"(≈${ctx * p * 2 / 1e6:.2f} по ценам API, в 20 раз дороже обычного шага, и каждый следующий шаг "
              f"снова читает {k(ctx)}).\n"
              f"Новая задача → /clear. Эта же задача, впереди много шагов → /handoff, затем /clear "
              f"(состояние подхватится само). Осталось пара шагов → отправь сообщение ещё раз в течение "
              f"{GUARD_BYPASS_MIN} мин, проверки не будет.")
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


def start(d):
    path = os.path.join(d.get("cwd") or os.getcwd(), HANDOFF)
    if d.get("source") not in ("clear", "startup") or not os.path.isfile(path):
        return
    age_h = (time.time() - os.path.getmtime(path)) / 3600
    if age_h > HANDOFF_FRESH_H:
        return
    text = open(path, encoding="utf-8", errors="ignore").read()[:3000]
    if d["source"] == "clear" and age_h <= HANDOFF_FULL_H:
        msg = (f"Состояние задачи из прошлой сессии ({HANDOFF}, обновлён {age_h:.0f} ч назад). "
               f"Если пользователь начинает другую задачу — не используй.\n\n{text}")
    else:
        first = next((l.strip("# ").strip() for l in text.splitlines() if l.strip()), "")
        msg = f"Есть {HANDOFF} ({age_h:.0f} ч назад): «{first[:150]}». Прочитай, если пользователь продолжает эту задачу."
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": msg}},
                     ensure_ascii=False))


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        {"status": status, "guard": guard, "start": start}[sys.argv[1]](json.loads(sys.stdin.buffer.read() or b"{}"))
    except Exception:
        pass
