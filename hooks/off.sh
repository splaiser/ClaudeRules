# Выключатели базы; подключается из хуков: `. off.sh; base_off <компонент> && exit 0`.
# Компоненты: guard (страж паузы), status (строка состояния), handoff (подхват handoff и
# подсказка про /clear), review (напоминание о ревью). Выключает любое из:
#   переменная окружения CLAUDE_BASE_HOOKS=off — всё сразу;
#   файл ~/.claude/claude-base-state/off/<компонент> — глобально;
#   строка с именем компонента в <проект>/.claude/claude-base-off — только этот проект.
# Управление — economy.sh (в чате: /economy).
BASE_COMPONENTS="guard status handoff review"
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
