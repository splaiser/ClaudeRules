# Каталог плагинов по проекту

Читается только из `/project-setup`. Решение — по выводу `measure.sh`.
Маркетплейсы: `claude-plugins-official` (встроен), `trailofbits`
(перед установкой: `claude plugin marketplace add trailofbits/skills`).

## LSP (навигация по символам + ошибки типов после каждой правки)

Ставить для языка, в котором ≥ 10 файлов. Плагин — только адаптер:
без бинарника языкового сервера он не работает.

| Язык (`langs`) | Плагин | Бинарник (`bin`) | Установка бинарника |
|---|---|---|---|
| ts | typescript-lsp | typescript-language-server | `npm install -g typescript-language-server typescript` |
| py | pyright-lsp | pyright-langserver | `npm install -g pyright` |
| go | gopls-lsp | gopls | `go install golang.org/x/tools/gopls@latest` |
| rs | rust-analyzer-lsp | rust-analyzer | `rustup component add rust-analyzer` |
| cs | csharp-lsp | csharp-ls | `dotnet tool install -g csharp-ls` |
| php | php-lsp | intelephense | `npm install -g intelephense` |
| c | clangd-lsp | clangd | вручную (LLVM) |
| java | jdtls-lsp | jdtls | вручную |
| bsl, gd, sol | — | — | официального плагина нет, пропустить |

Бинарника нет и нет npm/go/rustup/dotnet для установки → плагин не ставить,
в итоге назвать, чего не хватает.

## security-guidance@claude-plugins-official

Ставить, если `web` или `bots` не `none`: внешний ввод, токены, платежи.
Требует `python=yes`. Цена: в каждом ходе с правками — отдельный вызов модели
на ревью диффа. В плане назвать эту цену.

## frontend-design@claude-plugins-official

Ставить, если `ui` не `none` или `ui_files` ≥ 20. Скилл: грузится только когда нужен.

## Крипто (`crypto` не `none`)

- `building-secure-contracts@trailofbits` — сканеры уязвимостей Solana, TON,
  Cosmos, Cairo, Algorand, Substrate и гайды по EVM/ERC-токенам. Ставить при
  `contracts` или on-chain SDK (anchor, @ton/*, cosmwasm).
- `property-based-testing@trailofbits` — инварианты (Echidna/Medusa для Solidity,
  fast-check, Hypothesis). Ставить при `contracts`.
- Клиентские библиотеки без контрактов (только ethers/viem/web3) — ничего из
  этого, достаточно security-guidance по признаку `web`/`bots`.
Предупредить: это помощь, не аудит. Контракты с реальными деньгами — внешний аудит.

## supply-chain-risk-auditor@trailofbits

Ставить, если `crypto` не `none` или `bots`/`web` работают с платежами
(stripe, в `web`) — проверка зависимостей npm/PyPI/Go на известные уязвимости,
заброшенные пакеты и install-скрипты. Скилл: запускается по запросу.

## agent-sdk-dev@claude-plugins-official

Ставить, если в `agents` есть `claude-agent-sdk`, `@anthropic-ai/claude-agent-sdk`,
`anthropic` или `@anthropic-ai/sdk`. Другие фреймворки агентов (openai, langchain,
crewai, ai, mastra) — ничего, документацию даёт Context7.

## Игровые движки (`engine` не `none`) — только рекомендация, не установка

MCP к редактору требует аддона внутри движка, это ставится руками в редакторе.
- unity → MCP for Unity (CoplayDev), C# даёт csharp-lsp по `langs`.
- godot → Godot AI (от авторов MCP for Unity, в Asset Library).
- unreal → официального варианта нет, не предлагать.
Не предлагать решения, требующие облачного аккаунта стороннего сервиса.

## Не ставить из проекта

- Superpowers, feature-dev — конфликтуют с ponytail и базой.
- Context7 — ставится глобально установщиком базы.
- rtk и другие хуки сжатия вывода команд — в независимом замере JetBrains
  на 86 задачах сделали сессии дороже, а не дешевле.
- Сторонние скиллы для ботов (aiogram, grammY) — мелкие непроверенные репозитории;
  документацию фреймворков даёт Context7.
