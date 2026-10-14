#!/bin/bash
# Слияние settings.base.json с ~/.claude/settings.json: Claude Code сам пишет в этот файл, поэтому не замена.
# Компоненты, выключенные через economy.sh (файлы в claude-base-state/off/), в settings.json не попадают
# и убираются оттуда. Слияние — node или python; без них, если settings.json ещё нет, кладётся готовый файл базы.
# Вызывается из install.sh (он кладёт копию settings.base.json в claude-base-state) и из economy.sh.
set -euo pipefail
DST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE="$DST/claude-base-state"
export BASE="$STATE/settings.base.json" OUT="$DST/settings.json" MAN="$DST/claude-base.permissions.json"
export NEW="$OUT.new"
SKIP=""; for c in guard status handoff review compact; do [ -e "$STATE/off/$c" ] && SKIP="$SKIP $c"; done; export SKIP
[ -f "$BASE" ] || { echo "нет $BASE — запустите update-claude.sh"; exit 1; }
rm -f "$NEW"
PY=""; for c in python3 python py; do "$c" -c "import json" >/dev/null 2>&1 && { PY=$c; break; }; done
if command -v node >/dev/null; then node -e '
const fs = require("fs"), { BASE, OUT, MAN, NEW, SKIP } = process.env;
const read = f => fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : {};
const base = read(BASE), cur = read(OUT), prev = read(MAN);  // prev — правила, добавленные базой в прошлый раз
const skip = new Set(SKIP.split(" ").filter(Boolean));
for (const [c, ev] of Object.entries({ guard: "UserPromptSubmit", handoff: "SessionStart", review: "Stop" }))
  if (skip.has(c) && base.hooks) delete base.hooks[ev];     // выключенный компонент не ставится
if (skip.has("status")) {
  delete base.statusLine;
  if (cur.statusLine && JSON.stringify(cur.statusLine).includes("base-hooks")) delete cur.statusLine;  // чужую не трогать
}
if (skip.has("compact")) {
  if (cur.autoCompactWindow === base.autoCompactWindow) delete cur.autoCompactWindow;  // своё значение остаётся
  delete base.autoCompactWindow;
}
cur.env = { ...base.env, ...cur.env };                       // личные значения важнее базовых
for (const k of ["autoCompactWindow", "statusLine"]) if (base[k] !== undefined && cur[k] === undefined) cur[k] = base[k];
cur.permissions = cur.permissions || {};
for (const k of ["allow", "ask", "deny"]) {
  const now = base.permissions[k] || [];
  const gone = new Set((prev[k] || []).filter(r => !now.includes(r)));  // убранные из базы — убрать и здесь
  cur.permissions[k] = [...new Set([...(cur.permissions[k] || []).filter(r => !gone.has(r)), ...now])];
  if (!cur.permissions[k].length) delete cur.permissions[k];
}
fs.writeFileSync(MAN, JSON.stringify(base.permissions, null, 2) + "\n");
for (const ev of Object.keys(cur.hooks || {})) {             // убрать хуки базы (прошлых версий и текущей)
  cur.hooks[ev] = cur.hooks[ev].filter(g => !JSON.stringify(g).includes("base-hooks"));
  if (!cur.hooks[ev].length) delete cur.hooks[ev];
}
for (const [ev, groups] of Object.entries(base.hooks || {}))  // и поставить текущие
  (cur.hooks = cur.hooks || {})[ev] = [...(cur.hooks[ev] || []), ...groups];
if (cur.hooks && !Object.keys(cur.hooks).length) delete cur.hooks;
fs.writeFileSync(NEW, JSON.stringify(cur, null, 2) + "\n");
'
elif [ -n "$PY" ]; then "$PY" -c '
import json, os                                               # то же слияние, что в ветке node
E = os.environ
read = lambda f: json.load(open(f, encoding="utf-8")) if os.path.exists(f) else {}
base, cur, prev = read(E["BASE"]), read(E["OUT"]), read(E["MAN"])
skip = set(E["SKIP"].split())
for c, ev in {"guard": "UserPromptSubmit", "handoff": "SessionStart", "review": "Stop"}.items():
    if c in skip: base.get("hooks", {}).pop(ev, None)
if "status" in skip:
    base.pop("statusLine", None)
    if "base-hooks" in json.dumps(cur.get("statusLine", {})): cur.pop("statusLine", None)
if "compact" in skip:
    if cur.get("autoCompactWindow") == base.get("autoCompactWindow"): cur.pop("autoCompactWindow", None)
    base.pop("autoCompactWindow", None)
cur["env"] = {**base.get("env", {}), **cur.get("env", {})}
for k in ["autoCompactWindow", "statusLine"]:
    if k in base and k not in cur: cur[k] = base[k]
perms = cur.setdefault("permissions", {})
for k in ["allow", "ask", "deny"]:
    now = base.get("permissions", {}).get(k, [])
    gone = {r for r in prev.get(k, []) if r not in now}
    merged = list(dict.fromkeys([r for r in perms.get(k, []) if r not in gone] + now))
    if merged: perms[k] = merged
    else: perms.pop(k, None)
json.dump(base.get("permissions", {}), open(E["MAN"], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
hooks = cur.get("hooks", {})
for ev in list(hooks):
    hooks[ev] = [g for g in hooks[ev] if "base-hooks" not in json.dumps(g, ensure_ascii=False)]
    if not hooks[ev]: del hooks[ev]
for ev, groups in base.get("hooks", {}).items():
    hooks.setdefault(ev, []).extend(groups)
if hooks: cur["hooks"] = hooks
else: cur.pop("hooks", None)
json.dump(cur, open(E["NEW"], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
'
elif [ ! -f "$OUT" ] && [ -z "$SKIP" ]; then
  cp "$BASE" "$NEW"
  sed -n '/"permissions"/,/^  }/p' "$BASE" | sed '1s/.*"permissions": //; $s/},*$/}/' > "$MAN"
else
  echo "Нет node и python: слить настройки базы с вашим $OUT не могу."
  echo "Поставьте Node.js (winget install OpenJS.NodeJS.LTS) или Python и запустите установку снова."; exit 1
fi
# Записать, только если что-то изменилось; прежний файл — в бэкап вне skills/ и agents/.
if [ -f "$OUT" ] && cmp -s "$OUT" "$NEW"; then rm -f "$NEW"; else
  [ -f "$OUT" ] && { b="$DST/claude-base-backups/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$b"; cp "$OUT" "$b/settings.json"; }
  mv "$NEW" "$OUT"; echo "settings.json обновлён${SKIP:+ (выключено: ${SKIP# })}"
fi
