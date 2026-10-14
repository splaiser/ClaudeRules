#!/bin/bash
# Обёртка ctx.py: найти Python (на Windows python3 бывает заглушкой магазина). Нет Python — тихо выйти.
# Выключатели — off.sh / economy.sh. Выключенный компонент молчит (строка состояния пустая).
. "$(dirname "$0")/off.sh"
case "$1" in guard) comp=guard ;; status) comp=status ;; start) comp=handoff ;; *) exit 0 ;; esac
base_off "$comp" && exit 0
for c in python3 python py; do
  "$c" -c "" >/dev/null 2>&1 && exec "$c" -I "$(dirname "$0")/ctx.py" "$1"
done
exit 0
