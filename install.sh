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
for d in "$SRC"/skills/*/; do
  n=$(basename "$d")   # выключенный компонент не ставится вместе со своей командой
  if [ "$n" = handoff ] && [ -e "$DST/claude-base-state/off/handoff" ]; then rm -rf "$DST/skills/handoff"; continue; fi
  place "${d%/}" "$DST/skills/$n"
done
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

# settings.json не заменяется, а сливается (см. hooks/merge-settings.sh); копия настроек базы
# остаётся в claude-base-state, чтобы /economy мог переслить хуки без репозитория.
mkdir -p "$DST/claude-base-state"; cp "$SRC/settings.base.json" "$DST/claude-base-state/settings.base.json"
bash "$SRC/hooks/merge-settings.sh" || exit 1
echo "Готово: $DST. Проверка — /context и /hooks в новой сессии Claude Code."
