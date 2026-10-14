#!/bin/bash
# Хук Stop: напомнить о ревью, если с прошлого ревью накопились изменения выше порога гейта.
# Одно напоминание на состояние кода; сообщение мягкое (additionalContext), остановку не ломает.
# Выключить: economy.sh off review (или /economy), либо CLAUDE_BASE_HOOKS=off.
. "$(dirname "$0")/off.sh"; base_off review && exit 0
input=$(cat)
printf '%s' "$input" | grep -qE '"stop_hook_active" *: *true' && exit 0   # уже продолжаем по хуку

reason=$(bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/review/gate.sh" --hook 2>/dev/null) || exit 0
[ -n "$reason" ] || exit 0

msg="Гейт ревью: есть непроверенные изменения ($reason). Если задача закончена — проведи ревью по скиллу review. Если задача не закончена или ты ждёшь ответа пользователя — просто остановись: напоминание повторится только при новых изменениях."
msg=${msg//\\/\\\\}; msg=${msg//\"/\\\"}
printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"%s"}}\n' "$msg"
