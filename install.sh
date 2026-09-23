#!/bin/bash
# Подключает базу к ~/.claude. Повторный запуск безопасен (так же делается обновление).
# COPY=1 bash install.sh — копировать вместо симлинков (Windows без Developer Mode).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DST/skills" "$DST/agents"

place() {  # place <источник> <цель>
  if [ -e "$2" ] && [ ! -L "$2" ] && [ "${COPY:-0}" != 1 ]; then
    mv "$2" "$2.bak-$STAMP"; echo "бэкап: $2.bak-$STAMP"
  fi
  rm -rf "$2"
  if [ "${COPY:-0}" = 1 ]; then cp -R "$1" "$2"; else ln -s "$1" "$2"; fi
}

place "$SRC/CLAUDE.md" "$DST/CLAUDE.md"
rm -rf "$DST/base-hooks"   # хуки graphify из прошлых версий базы больше не нужны
for d in "$SRC"/skills/*/; do place "${d%/}" "$DST/skills/$(basename "$d")"; done
for f in "$SRC"/agents/*.md; do place "$f" "$DST/agents/$(basename "$f")"; done

# settings.json не заменяется, а сливается: Claude Code сам пишет в этот файл.
command -v node >/dev/null || { echo "Нет node: перенеси settings.base.json в $DST/settings.json вручную"; exit 1; }
[ -f "$DST/settings.json" ] && cp "$DST/settings.json" "$DST/settings.json.bak-$STAMP"
BASE="$SRC/settings.base.json" OUT="$DST/settings.json" node -e '
const fs = require("fs"), { BASE, OUT } = process.env;
const base = JSON.parse(fs.readFileSync(BASE, "utf8"));
const cur = fs.existsSync(OUT) ? JSON.parse(fs.readFileSync(OUT, "utf8")) : {};
cur.env = { ...base.env, ...cur.env };                       // личные значения важнее базовых
cur.permissions = cur.permissions || {};
cur.permissions.allow = [...new Set([...(cur.permissions.allow || []), ...base.permissions.allow])];
for (const ev of Object.keys(cur.hooks || {})) {             // убрать хуки прошлых версий базы
  cur.hooks[ev] = cur.hooks[ev].filter(g => !JSON.stringify(g).includes("base-hooks"));
  if (!cur.hooks[ev].length) delete cur.hooks[ev];
}
if (cur.hooks && !Object.keys(cur.hooks).length) delete cur.hooks;
fs.writeFileSync(OUT, JSON.stringify(cur, null, 2) + "\n");
'
echo "Готово: $DST. Проверка — /context и /hooks в новой сессии Claude Code."
