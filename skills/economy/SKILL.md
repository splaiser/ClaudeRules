---
name: economy
description: Включить или выключить экономию токенов базы (страж паузы, строка состояния, handoff, напоминание о ревью) для всех проектов или для текущего. Только вручную.
disable-model-invocation: true
argument-hint: status | off [guard|status|handoff|review|compact] [--project] | on [...] [--project]
---

Выполни одну команду и покажи её вывод как есть, без пересказа и советов:

    bash ~/.claude/claude-base-hooks/economy.sh $ARGUMENTS

Аргументов нет — это `status`. Действует сразу, перезапуск не нужен.
Без `--project` компонент убирается из `settings.json` для всех проектов (нужно, когда его
заменяет другой инструмент); `--project` — хуки молчат только в проекте текущей папки.
Если в выводе есть «команду /handoff вернёт ~/update-claude.sh» — передай это пользователю.
