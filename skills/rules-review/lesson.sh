#!/bin/bash
# Урок в журнал проекта. Журнал лежит вне репозитория и в коммиты не попадает:
# ~/.claude/lessons/<папка-проекта>-<хеш пути>.md; разобранное — в <то же>.archive.md.
#   lesson.sh "что сделал" "как правильно" "почему"   дописать урок
#   lesson.sh --path                                   путь к журналу текущего проекта
REMIND=10   # столько необработанных записей — пора /rules-review
set -euo pipefail
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lessons"
file="$dir/$(basename "$root")-$(printf %s "$root" | git hash-object --stdin | cut -c1-8).md"
[ "${1:-}" = --path ] && { echo "$file"; exit 0; }
[ $# -eq 3 ] || { echo 'использование: lesson.sh "что сделал" "как правильно" "почему"' >&2; exit 2; }

mkdir -p "$dir"
[ -f "$file" ] || printf '# Уроки: %s\n<!-- rules-review: запусков=0 записей=0 шум=0 замер=нет -->\n\n' "$root" > "$file"
printf '%s | %s | %s | %s\n' "$(date +%F)" "${1//|//}" "${2//|//}" "${3//|//}" >> "$file"
n=$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} \|' "$file" || true)
echo "записано: $file (необработанных: $n)"
[ "$n" -lt "$REMIND" ] || echo "необработанных уроков $n — предложи пользователю /rules-review"
