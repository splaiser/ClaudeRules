#!/bin/bash
# Установка базы из этой папки и проверка. Запускается из ~/update-claude.sh после git pull.
SRC="$(cd "$(dirname "$0")" && pwd)"
ok() { echo "  ок: $*"; }; bad() { echo "  НЕТ: $*"; FAIL=1; }
FAIL=0

# Куда смотрит Claude Code: на Windows — %USERPROFILE%\.claude, в Git Bash HOME может отличаться.
TARGETS=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}")
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    export COPY=1
    if [ -n "${USERPROFILE:-}" ] && command -v cygpath >/dev/null; then
      UP="$(cygpath -u "$USERPROFILE")/.claude"
      [ "$UP" -ef "${TARGETS[0]}" ] || { echo "Git Bash и Claude Code смотрят в разные папки — ставлю в обе"; TARGETS+=("$UP"); }
    fi ;;
esac

for T in "${TARGETS[@]}"; do
  echo "== Устанавливаю в $T"
  mkdir -p "$T"
  CLAUDE_CONFIG_DIR="$T" bash "$SRC/install.sh" || echo "!! установщик завершился с ошибкой — сообщение выше"
  echo "== Проверяю $T"
  for s in review rules-review long-task project-setup human-text; do
    [ -e "$T/skills/$s/SKILL.md" ] && ok "навык $s" || bad "навык $s"
  done
  [ -e "$T/claude-base-hooks/stop-review.sh" ] && ok "скрипт хука ревью" || bad "скрипт хука ревью"
  S="$T/settings.json"
  grep -q "stop-review.sh" "$S" 2>/dev/null && ok "хук ревью в settings.json" || bad "хук ревью в settings.json"
  grep -q '"autoCompactWindow"' "$S" 2>/dev/null && ok "окно сжатия" || bad "окно сжатия"
  grep -q '"ask"' "$S" 2>/dev/null && ok "правила для .env" || bad "правила для .env"
  grep -q "rules-review" "$T/CLAUDE.md" 2>/dev/null && ok "CLAUDE.md новой версии" || bad "CLAUDE.md новой версии"
done

echo
if [ "$FAIL" = 0 ]; then
  echo "Готово. Полностью закройте и заново откройте Claude Code, затем проверьте:"
  echo "  /rules-review есть в подсказках, /context показывает «/ 300k», /hooks показывает stop-review.sh"
else
  echo "Есть строки «НЕТ» — пришлите весь вывод."
fi
