#!/bin/bash
# Обёртка ctx.py: найти Python (на Windows python3 бывает заглушкой магазина). Нет Python — тихо выйти.
# Выключить хуки: CLAUDE_BASE_HOOKS=off (строка состояния остаётся).
[ "$1" != status ] && [ "${CLAUDE_BASE_HOOKS:-on}" = off ] && exit 0
for c in python3 python py; do
  "$c" -c "" >/dev/null 2>&1 && exec "$c" -I "$(dirname "$0")/ctx.py" "$1"
done
exit 0
