#!/bin/bash
# Выключатель экономии токенов и напоминаний базы.
#   economy.sh status                        что включено, а что выключено и кем
#   economy.sh off [компоненты] [--project]  выключить (без списка — всё)
#   economy.sh on  [компоненты] [--project]  включить обратно
# --project — только для проекта в текущей папке (файл .claude/claude-base-off, в git не попадает).
# Без --project — для всех проектов. Действует сразу, перезапуск Claude Code не нужен.
. "$(dirname "$0")/off.sh"
declare -A DESC=(
  [guard]="страж паузы: не пускает первое сообщение в остывшую большую сессию"
  [status]="строка состояния внизу: контекст, кеш, лимиты"
  [handoff]="подхват handoff после /clear и подсказка про /clear между задачами"
  [review]="напоминание о ревью в конце хода (хук Stop; сам /review и gate.sh работают всегда)")
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
    fi
    bash "$0" status ;;
  *) echo "использование: economy.sh status | off [компоненты] [--project] | on [компоненты] [--project]" >&2; exit 2 ;;
esac
