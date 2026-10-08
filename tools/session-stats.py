"""Куда уходят токены в сессиях Claude Code: разбор истории ~/.claude/projects/*/*.jsonl.

python3 tools/session-stats.py [файл.jsonl ...]   без аргументов — 10 последних сессий
Данные только читаются; модель не вызывается.
"""
import glob, json, os, re, sys
from datetime import datetime
from collections import Counter, defaultdict

# $/1M токенов: вход, выход, чтение кеша. Запись в кеш: 5 мин = 1.25× входа, 1 час = 2× входа.
PRICES = {"opus": (4.0, 20.0, 0.20), "sonnet": (2.0, 10.0, 0.20), "haiku": (1.0, 5.0, 0.10), "fable": (10.0, 50.0, 0.25)}
RU_CPT, EN_CPT = 2.45, 3.2   # символов на токен, замер этой базы (experiments/language-tokens)
CYR = re.compile(r"[А-Яа-яЁё]")
LAT = re.compile(r"[A-Za-z]")


def price(model):
    for k, p in PRICES.items():
        if k in (model or ""):
            return p
    return PRICES["sonnet"]


def texts(content, names):
    """(категория, текст, инструмент) для блоков сообщения; names: id вызова -> имя инструмента."""
    if isinstance(content, str):
        yield "text", content, None
        return
    for b in content or []:
        t = b.get("type")
        if t == "text":
            yield "text", b.get("text", ""), None
        elif t == "tool_use":
            names[b.get("id")] = b.get("name")
            yield "tool_input", json.dumps(b.get("input", {}), ensure_ascii=False), b.get("name")
        elif t == "tool_result":
            c = b.get("content")
            text = c if isinstance(c, str) else " ".join(x.get("text", "") for x in c or [] if isinstance(x, dict))
            yield "tool_result", text, names.get(b.get("tool_use_id"))


def analyze(path):
    seen, usage, chars, cyr, by_tool, names = set(), Counter(), Counter(), Counter(), Counter(), {}
    calls, max_ctx, models, big = 0, 0, Counter(), []
    cost = ru_cost = rewrite_cost = 0.0
    rewrites, last_t = 0, None
    extra_now = 0.0          # переплата за русский, накопленная в контексте к текущему вызову, токенов
    per_char = 1 / RU_CPT - 1 / EN_CPT
    for line in open(path, encoding="utf-8"):
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        m = d.get("message") or {}
        if d.get("type") == "assistant" and m.get("usage"):
            key = m.get("id") or d.get("requestId") or d.get("uuid")
            if key not in seen:          # один ответ API записан несколькими строками с одним usage
                seen.add(key)
                u = m["usage"]
                pi, po, pr = price(m.get("model"))
                cc = u.get("cache_creation") or {}
                w1h, w5m = cc.get("ephemeral_1h_input_tokens", 0), cc.get("ephemeral_5m_input_tokens", 0)
                if not cc:
                    w5m = u.get("cache_creation_input_tokens", 0)
                for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"):
                    usage[k] += u.get(k, 0)
                cost += (u.get("input_tokens", 0) * pi + w5m * pi * 1.25 + w1h * pi * 2
                         + u.get("cache_read_input_tokens", 0) * pr + u.get("output_tokens", 0) * po) / 1e6
                ru_cost += extra_now * pr / 1e6          # русский из истории перечитывается на каждом вызове
                t = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00")) if d.get("timestamp") else None
                w = u.get("cache_creation_input_tokens", 0)
                if t and last_t and (t - last_t).total_seconds() > 3300 and w > 50000:
                    rewrites += 1                            # кеш истёк за паузу — весь контекст записан заново
                    rewrite_cost += (w5m * pi * 1.25 + w1h * pi * 2) / 1e6
                last_t = t or last_t
                ctx = u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                max_ctx = max(max_ctx, ctx)
                calls += 1
                models[m.get("model")] += 1
        if d.get("type") in ("user", "assistant") and not d.get("isMeta"):
            role = "you" if d["type"] == "user" else "claude"
            for cat, t, tool in texts(m.get("content"), names):
                if tool:
                    by_tool[tool] += len(t)
                name = {"text": f"{role}_text"}.get(cat, cat)
                n_cyr = len(CYR.findall(t))
                chars[name] += len(t)
                cyr[name] += n_cyr
                extra_now += n_cyr * per_char
                pi, po, pr = price(m.get("model") or next(iter(models), ""))
                ru_cost += n_cyr * per_char * pi * 2 / 1e6           # однократная запись в кеш
                if name == "claude_text":
                    ru_cost += n_cyr * per_char * po / 1e6           # и как выходные токены
                if cat == "tool_result" and len(t) > 20000:
                    big.append(len(t))
    return dict(rewrites=rewrites, rewrite_cost=rewrite_cost, by_tool=by_tool, path=path, calls=calls, usage=usage, cost=cost, ru_cost=ru_cost, max_ctx=max_ctx, models=models,
                chars=chars, cyr=cyr, big=sorted(big, reverse=True)[:5])


def report(r):
    u = r["usage"]
    ctx_total = u["input_tokens"] + u["cache_creation_input_tokens"] + u["cache_read_input_tokens"]
    hit = u["cache_read_input_tokens"] / ctx_total if ctx_total else 0
    print(f"\n== {os.path.basename(r['path'])}  модели: {dict(r['models'])}")
    print(f"вызовов API: {r['calls']}, оценка стоимости: ${r['cost']:.2f}, контекст в конце до {r['max_ctx']:,} токенов")
    print(f"вход {u['input_tokens']:,} | запись в кеш {u['cache_creation_input_tokens']:,} | чтение кеша "
          f"{u['cache_read_input_tokens']:,} | выход {u['output_tokens']:,} | попадание в кеш {100 * hit:.0f}%")
    print("состав истории (символы; доля кириллицы среди всех символов категории):")
    ru_tokens = en_equiv = 0
    for cat in ("you_text", "claude_text", "tool_input", "tool_result"):
        c, k = r["chars"][cat], r["cyr"][cat]
        share = k / c if c else 0
        tok = k / RU_CPT + (c - k) / EN_CPT          # грубая оценка токенов категории
        ru_tokens += k / RU_CPT
        en_equiv += k / EN_CPT
        print(f"  {cat:12} {c:>10,} симв. ≈{tok:>9,.0f} ток.  кириллица {100 * share:4.0f}%")
    extra = ru_tokens - en_equiv
    print(f"русский текст в истории ≈{extra:,.0f} лишних токенов против английского; переплата за сессию "
          f"≈${r['ru_cost']:.2f} из ${r['cost']:.2f} ({100 * r['ru_cost'] / max(r['cost'], 1e-9):.1f}%, верхняя оценка)")
    if r["rewrites"]:
        print(f"возвратов после паузы больше часа с перезаписью кеша: {r['rewrites']}, это ≈${r['rewrite_cost']:.2f} "
              f"({100 * r['rewrite_cost'] / max(r['cost'], 1e-9):.0f}% стоимости)")
    avg = ctx_total / r["calls"] if r["calls"] else 0
    print(f"средний контекст на вызов ≈{avg:,.0f} токенов — столько перечитывается при каждом ответе")
    top = r["by_tool"].most_common(6)
    if top:
        print("инструменты по объёму в истории (вызов + результат, символы):", ", ".join(f"{k} {v:,}" for k, v in top))
    if r["big"]:
        print("самые большие выводы инструментов (символы):", ", ".join(f"{b:,}" for b in r["big"]))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")   # консоль Windows по умолчанию cp1251
    files = sys.argv[1:] or sorted(glob.glob(os.path.expanduser(
        os.path.join(os.environ.get("CLAUDE_CONFIG_DIR", "~/.claude"), "projects", "*", "*.jsonl"))),
        key=os.path.getmtime)[-10:]
    for f in files:
        report(analyze(f))
