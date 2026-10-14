# Выключатели базы; подключается из хуков: `. off.sh; base_off <компонент> && exit 0`.
# Компоненты: guard (страж паузы), status (строка состояния), handoff (подхват handoff, подсказка
# про /clear и команда /handoff), review (напоминание о ревью), compact (окно автосжатия).
# Выключает любое из:
#   переменная окружения CLAUDE_BASE_HOOKS=off — все хуки, молча;
#   файл ~/.claude/claude-base-state/off/<компонент> — глобально; economy.sh заодно убирает
#     компонент из settings.json (merge-settings.sh), и обновления базы его не возвращают;
#   строка с именем компонента в <проект>/.claude/claude-base-off — хуки этого проекта молчат.
# Управление — economy.sh (в чате: /economy).
BASE_COMPONENTS="guard status handoff review compact"
BASE_OFF_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claude-base-state/off"
base_off_why() {   # base_off_why <компонент> → причина выключения, код 0; включён → код 1
  if [ "${CLAUDE_BASE_HOOKS:-on}" = off ]; then echo "CLAUDE_BASE_HOOKS=off"; return 0; fi
  if [ -e "$BASE_OFF_DIR/$1" ]; then echo "глобально"; return 0; fi
  if [ -f "$PWD/.claude/claude-base-off" ] && tr -d '\r' < "$PWD/.claude/claude-base-off" | grep -qxF "$1"; then
    echo "этим проектом"; return 0
  fi
  return 1
}
base_off() { base_off_why "$1" >/dev/null; }
