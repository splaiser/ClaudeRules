#!/bin/bash
# Подключает базу к ~/.claude. Повторный запуск безопасен (так же делается обновление).
# COPY=1 bash install.sh — копировать вместо симлинков (Windows без Developer Mode).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DST/skills" "$DST/agents"

place() {  # place <источник> <цель>
  # Бэкап, если на месте цели свой файл: в режиме COPY старая копия без правок не бэкапится.
  if [ -e "$2" ] && [ ! -L "$2" ] && ! diff -rq "$1" "$2" >/dev/null 2>&1; then
    mv "$2" "$2.bak-$STAMP"; echo "бэкап: $2.bak-$STAMP"
  fi
  rm -rf "$2"
  if [ "${COPY:-0}" = 1 ]; then cp -R "$1" "$2"; else ln -s "$1" "$2"; fi
}

place "$SRC/CLAUDE.md" "$DST/CLAUDE.md"
rm -rf "$DST/base-hooks"   # хуки graphify из прошлых версий базы больше не нужны
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
command -v node >/dev/null || { echo "Нет node: перенеси settings.base.json в $DST/settings.json вручную"; exit 1; }
[ -f "$DST/settings.json" ] && cp "$DST/settings.json" "$DST/settings.json.bak-$STAMP"
BASE="$SRC/settings.base.json" OUT="$DST/settings.json" MAN="$DST/claude-base.permissions.json" node -e '
const fs = require("fs"), { BASE, OUT, MAN } = process.env;
const read = f => fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : {};
const base = read(BASE), cur = read(OUT), prev = read(MAN);  // prev — правила, добавленные базой в прошлый раз
cur.env = { ...base.env, ...cur.env };                       // личные значения важнее базовых
cur.permissions = cur.permissions || {};
for (const k of ["allow", "ask", "deny"]) {
  const now = base.permissions[k] || [];
  const gone = new Set((prev[k] || []).filter(r => !now.includes(r)));  // убранные из базы — убрать и здесь
  cur.permissions[k] = [...new Set([...(cur.permissions[k] || []).filter(r => !gone.has(r)), ...now])];
  if (!cur.permissions[k].length) delete cur.permissions[k];
}
fs.writeFileSync(MAN, JSON.stringify(base.permissions, null, 2) + "\n");
for (const ev of Object.keys(cur.hooks || {})) {             // убрать хуки прошлых версий базы
  cur.hooks[ev] = cur.hooks[ev].filter(g => !JSON.stringify(g).includes("base-hooks"));
  if (!cur.hooks[ev].length) delete cur.hooks[ev];
}
if (cur.hooks && !Object.keys(cur.hooks).length) delete cur.hooks;
fs.writeFileSync(OUT, JSON.stringify(cur, null, 2) + "\n");
'
echo "Готово: $DST. Проверка — /context и /hooks в новой сессии Claude Code."
