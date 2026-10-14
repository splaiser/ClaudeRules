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
  off() { [ -e "$T/claude-base-state/off/$1" ]; }   # выключено вами через /economy — не ошибка
  off handoff && ok "handoff выключен вами (/economy)" || { [ -e "$T/skills/handoff/SKILL.md" ] && ok "навык handoff" || bad "навык handoff"; }
  [ -e "$T/skills/economy/SKILL.md" ] && [ -e "$T/claude-base-hooks/economy.sh" ] && [ -e "$T/claude-base-hooks/off.sh" ] \
    && ok "выключатель /economy" || bad "выключатель /economy"
  PYOK=; for c in python3 python py; do
    "$c" -c "" >/dev/null 2>&1 && { PYOK=1; break; }; done
  [ -n "${PYOK:-}" ] && ok "Python для хуков контекста" || bad "Python для хуков контекста (страж паузы и строка состояния без него молчат)"
  S="$T/settings.json"
  off review && ok "напоминание о ревью выключено вами (/economy)" || { grep -q "stop-review.sh" "$S" 2>/dev/null && ok "хук ревью в settings.json" || bad "хук ревью в settings.json"; }
  off guard && ok "страж паузы выключен вами (/economy)" || { grep -qE 'ctx\.sh[\\"]* guard' "$S" 2>/dev/null && ok "страж паузы в settings.json" || bad "страж паузы в settings.json"; }
  off status && ok "строка состояния выключена вами (/economy)" || { grep -qE 'ctx\.sh[\\"]* status' "$S" 2>/dev/null && ok "строка состояния базы" \
    || echo "  инфо: строка состояния — ваша собственная, база её не заменяет"; }
  off compact && ok "окно сжатия выключено вами (/economy)" || { grep -q '"autoCompactWindow"' "$S" 2>/dev/null && ok "окно сжатия" || bad "окно сжатия"; }
  grep -q '"ask"' "$S" 2>/dev/null && ok "правила для .env" || bad "правила для .env"
  grep -q "rules-review" "$T/CLAUDE.md" 2>/dev/null && ok "CLAUDE.md новой версии" || bad "CLAUDE.md новой версии"
done

echo
if [ "$FAIL" = 0 ]; then
  echo "Готово. Полностью закройте и заново откройте Claude Code, затем проверьте:"
  if ls "${TARGETS[0]}"/claude-base-state/off/* >/dev/null 2>&1; then
    echo "  часть компонентов выключена вами: /economy status (вернуть: /economy on, затем снова update-claude.sh)"
  else
    echo "  /rules-review, /handoff и /economy есть в подсказках, /context показывает «/ 300k», внизу строка «контекст … · кеш …»"
  fi
  echo "Как работать экономно: ~/claude-base/TOKENS.md"
else
  echo "Есть строки «НЕТ» — пришлите весь вывод."
fi
