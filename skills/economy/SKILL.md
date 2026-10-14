---
name: economy
description: Включить или выключить экономию токенов базы (страж паузы, строка состояния, handoff, напоминание о ревью) для всех проектов или для текущего. Только вручную.
disable-model-invocation: true
argument-hint: status | off [guard|status|handoff|review] [--project] | on [...] [--project]
---

Выполни одну команду и покажи её вывод как есть, без пересказа и советов:

    bash ~/.claude/claude-base-hooks/economy.sh $ARGUMENTS

Аргументов нет — это `status`. Действует сразу, перезапуск не нужен.
`--project` — только для проекта в текущей папке; без него — для всех проектов.
