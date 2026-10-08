#!/bin/bash
# Подключает базу к ~/.claude. Повторный запуск безопасен (так же делается обновление).
# COPY=1 bash install.sh — копировать вместо симлинков (Windows без Developer Mode).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DST/skills" "$DST/agents"

BACKUPS="$DST/claude-base-backups/$STAMP"   # бэкапы — вне skills/ и agents/, чтобы не стать навыками
INSTALLED="$DST/claude-base-installed.txt"  # отпечатки того, что установщик положил в прошлый раз
touch "$INSTALLED"
fp() {  # отпечаток файла или папки (относительные пути + содержимое)
  if [ -d "$1" ]; then (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s\n' "$f"; cat "$f"; done) | cksum
  else cksum < "$1"; fi | cut -d' ' -f1
}
place() {  # place <источник> <цель>
  local rel="${2#$DST/}" cur
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    cur=$(fp "$2")
    # Бэкап только своего: не прошлая копия базы и не совпадает с новой.
    if [ "$cur" != "$(fp "$1")" ] && ! grep -qxF "$rel	$cur" "$INSTALLED"; then
      mkdir -p "$(dirname "$BACKUPS/$rel")"; mv "$2" "$BACKUPS/$rel"; echo "бэкап: $BACKUPS/$rel"
    fi
  fi
  rm -rf "$2"
  if [ "${COPY:-0}" = 1 ]; then cp -R "$1" "$2"; else ln -s "$1" "$2"; fi
  { grep -v "^$rel	" "$INSTALLED" || true; [ "${COPY:-0}" = 1 ] && printf '%s\t%s\n' "$rel" "$(fp "$2")"; } > "$INSTALLED.tmp"
  mv "$INSTALLED.tmp" "$INSTALLED"
}
# Бэкапы прошлых версий установщика лежали рядом с навыками — убрать оттуда.
for b in "$DST"/skills/*.bak-* "$DST"/agents/*.bak-* "$DST"/CLAUDE.md.bak-*; do
  [ -e "$b" ] || continue
  mkdir -p "$DST/claude-base-backups/old"; mv "$b" "$DST/claude-base-backups/old/"; echo "перенесён старый бэкап: $(basename "$b")"
done

place "$SRC/CLAUDE.md" "$DST/CLAUDE.md"
rm -rf "$DST/base-hooks"   # хуки graphify из прошлых версий базы больше не нужны
place "$SRC/hooks" "$DST/claude-base-hooks"
for d in "$SRC"/skills/*/; do place "${d%/}" "$DST/skills/$(basename "$d")"; done
for f in "$SRC"/agents/*.md; do place "$f" "$DST/agents/$(basename "$f")"; done
for l in "$DST"/skills/* "$DST"/agents/*; do   # симлинки на удалённые из базы файлы
  [ -L "$l" ] && [ ! -e "$l" ] && case "$(readlink "$l")" in
    "$SRC"/*) rm "$l"; echo "удалён устаревший: $l" ;; esac
done

# Глобальные плагины. Повторная установка безопасна.
# ponytail: на него ссылаются CLAUDE.md, reviewer и long-task.
MARKETPLACES=("DietrichGebert/ponytail")
PLUGINS=("context7@claude-plugins-official" "ponytail@ponytail")
if command -v claude >/dev/null; then
  for m in "${MARKETPLACES[@]}"; do claude plugin marketplace add "$m" >/dev/null 2>&1 || true; done
  for p in "${PLUGINS[@]}"; do claude plugin install "$p" --scope user >/dev/null 2>&1 \
    && echo "плагин: $p" || echo "не удалось поставить $p — в Claude Code: /plugin install $p"; done
else
  echo "claude не найден в PATH — поставь вручную в Claude Code: /plugin install ${PLUGINS[*]}"
fi

# settings.json не заменяется, а сливается: Claude Code сам пишет в этот файл.
# Слияние — node или python; без них, если settings.json ещё нет, кладётся готовый файл базы.
export BASE="$SRC/settings.base.json" OUT="$DST/settings.json" MAN="$DST/claude-base.permissions.json"
[ -f "$OUT" ] && cp "$OUT" "$OUT.bak-$STAMP"
PY=""; for c in python3 python py; do "$c" -c "import json" >/dev/null 2>&1 && { PY=$c; break; }; done
if command -v node >/dev/null; then node -e '
const fs = require("fs"), { BASE, OUT, MAN } = process.env;
const read = f => fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : {};
const base = read(BASE), cur = read(OUT), prev = read(MAN);  // prev — правила, добавленные базой в прошлый раз
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
fs.writeFileSync(OUT, JSON.stringify(cur, null, 2) + "\n");
'
elif [ -n "$PY" ]; then "$PY" -c '
import json, os                                               # то же слияние, что в ветке node
E = os.environ
read = lambda f: json.load(open(f, encoding="utf-8")) if os.path.exists(f) else {}
base, cur, prev = read(E["BASE"]), read(E["OUT"]), read(E["MAN"])
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
json.dump(cur, open(E["OUT"], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
'
elif [ ! -f "$OUT" ]; then
  cp "$BASE" "$OUT"
  sed -n '/"permissions"/,/^  }/p' "$BASE" | sed '1s/.*"permissions": //; $s/},*$/}/' > "$MAN"
else
  echo "Нет node и python: слить настройки базы с вашим $OUT не могу."
  echo "Поставьте Node.js (winget install OpenJS.NodeJS.LTS) и запустите установку снова."; exit 1
fi
echo "Готово: $DST. Проверка — /context и /hooks в новой сессии Claude Code."
