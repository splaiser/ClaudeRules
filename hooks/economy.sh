#!/bin/bash
# Выключатель экономии токенов и напоминаний базы.
#   economy.sh status                        что включено, а что выключено и кем
#   economy.sh off [компоненты] [--project]  выключить (без списка — всё)
#   economy.sh on  [компоненты] [--project]  включить обратно
# Без --project — для всех проектов: компонент убирается из ~/.claude/settings.json (хуки, строка
# состояния, окно сжатия) и, для handoff, команда /handoff; обновления базы его не возвращают.
# Нужно, когда другой инструмент делает то же самое и их нельзя оставлять вместе.
# --project — хуки молчат только в проекте текущей папки (файл .claude/claude-base-off, в git не попадает).
# Хуки в уже открытых сессиях пропадают после перезапуска Claude Code; молчат они сразу.
. "$(dirname "$0")/off.sh"
declare -A DESC=(
  [guard]="страж паузы: не пускает первое сообщение в остывшую большую сессию"
  [status]="строка состояния внизу: контекст, кеш, лимиты"
  [handoff]="подхват handoff после /clear и подсказка про /clear между задачами"
  [review]="напоминание о ревью в конце хода (хук Stop; сам /review и gate.sh работают всегда)"
  [compact]="окно автосжатия 300k в settings.json (если задано не вами; настройки проекта не трогает)")
cmd="${1:-status}"; shift 2>/dev/null
project=0; names=()
for a in "$@"; do
  case "$a" in
    --project) project=1 ;;
    all) names+=($BASE_COMPONENTS) ;;
    *) case " $BASE_COMPONENTS " in *" $a "*) names+=("$a") ;;
         *) echo "неизвестный компонент: $a (есть: $BASE_COMPONENTS, all)" >&2; exit 2 ;; esac ;;
  esac
done
[ ${#names[@]} -gt 0 ] || names=($BASE_COMPONENTS)
if [ $project = 1 ]; then   # окно сжатия на уровень проекта этим файлом не переключается
  case " ${names[*]} " in *" compact "*) [ $# -gt 1 ] && echo "compact проектом не выключается: уберите autoCompactWindow из .claude/settings.json проекта" >&2 ;; esac
  names=("${names[@]/compact}"); names=(${names[@]})
fi
pf="$PWD/.claude/claude-base-off"

case "$cmd" in
  status)
    for c in $BASE_COMPONENTS; do
      if why=$(base_off_why "$c"); then s="ВЫКЛЮЧЕН ($why)"; else s="включён"; fi
      printf '%-8s %-26s %s\n' "$c" "$s" "${DESC[$c]}"
    done ;;
  off|on)
    if [ $project = 1 ]; then
      mkdir -p "$PWD/.claude"; touch "$pf"
      for c in "${names[@]}"; do
        tr -d '\r' < "$pf" | grep -vxF "$c" > "$pf.tmp"; mv "$pf.tmp" "$pf"
        [ "$cmd" = off ] && echo "$c" >> "$pf"
      done
      [ -s "$pf" ] || rm -f "$pf"
      if [ -f "$pf" ] && ex=$(git rev-parse --git-path info/exclude 2>/dev/null); then   # локально, в коммиты не попадает
        grep -qxF ".claude/claude-base-off" "$ex" 2>/dev/null || { mkdir -p "$(dirname "$ex")"; echo ".claude/claude-base-off" >> "$ex"; }
      fi
    else
      mkdir -p "$BASE_OFF_DIR"
      for c in "${names[@]}"; do
        if [ "$cmd" = off ]; then touch "$BASE_OFF_DIR/$c"; else rm -f "$BASE_OFF_DIR/$c"; fi
      done
      case " ${names[*]} " in *" handoff "*) [ "$cmd" = off ] && rm -rf "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/handoff" ;; esac
      bash "$(dirname "$0")/merge-settings.sh" || echo "settings.json не обновлён: хуки молчат, но остались записаны в нём" >&2
      [ "$cmd" = on ] && case " ${names[*]} " in *" handoff "*) echo "команду /handoff вернёт ~/update-claude.sh" ;; esac
    fi
    bash "$0" status ;;
  *) echo "использование: economy.sh status | off [компоненты] [--project] | on [компоненты] [--project]" >&2; exit 2 ;;
esac
