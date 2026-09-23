#!/bin/bash
# Замер проекта для /project-setup: размер, языки, фреймворки, программы.
# Пороги — эвристика, правь под себя.
FILES_BIG=150; LINES_BIG=20000; DOCS_KB_BIG=150; FILES_MID=50

CODE=('*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.py' '*.go' '*.rs' '*.java' '*.kt'
      '*.cs' '*.rb' '*.php' '*.swift' '*.c' '*.cpp' '*.h' '*.vue' '*.svelte' '*.sql'
      '*.bsl' '*.os' '*.gd' '*.sol' '*.move' '*.cairo' '*.fc' '*.tact')
SKIP=(':!:*.min.*' ':!:*/dist/*' ':!:*/build/*' ':!:*/vendor/*' ':!:*/node_modules/*')
DOCS=('*.md' '*.mdx' '*.pdf' '*.docx' '*.txt')
MANIFESTS=('package.json' '*/package.json' 'requirements*.txt' '*/requirements*.txt'
           'pyproject.toml' '*/pyproject.toml' 'go.mod' 'pom.xml' 'build.gradle*'
           'composer.json' '*.csproj' 'Cargo.toml' '*/Cargo.toml')

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  list()  { git ls-files -- "$@" "${SKIP[@]}"; }
  list0() { git ls-files -z -- "$@" "${SKIP[@]}"; }
else
  echo "note: не git-репозиторий, замер по find (менее точный)"
  _find() { local n=(); for p in "$@"; do n+=(-o -name "${p##*/}"); done
    find . \( -path '*/node_modules' -o -path '*/.git' -o -path '*/dist' -o -path '*/build' \
      -o -path '*/vendor' \) -prune -o -type f \( "${n[@]:1}" \) "$PRINT"; }
  list()  { PRINT=-print  _find "$@"; }
  list0() { PRINT=-print0 _find "$@"; }
fi

files=$(list "${CODE[@]}" | wc -l)
lines=$(list0 "${CODE[@]}" | xargs -0 cat 2>/dev/null | wc -l)
docs_kb=$(( $(list0 "${DOCS[@]}" | xargs -0 cat 2>/dev/null | wc -c) / 1024 ))

if [ "$files" -ge "$FILES_BIG" ] || [ "$lines" -ge "$LINES_BIG" ]; then verdict=LARGE_CODE
elif [ "$docs_kb" -ge "$DOCS_KB_BIG" ]; then verdict=LARGE_DOCS
elif [ "$files" -ge "$FILES_MID" ]; then verdict=BORDERLINE
else verdict=SMALL; fi
echo "size: files=$files lines=$lines docs_kb=$docs_kb verdict=$verdict"

cnt() { list "$@" | wc -l | tr -d ' '; }
echo "langs: ts=$(cnt '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs') py=$(cnt '*.py') go=$(cnt '*.go')" \
     "rs=$(cnt '*.rs') cs=$(cnt '*.cs') java=$(cnt '*.java') php=$(cnt '*.php')" \
     "c=$(cnt '*.c' '*.cpp' '*.h') bsl=$(cnt '*.bsl' '*.os') gd=$(cnt '*.gd')" \
     "sol=$(cnt '*.sol') ui_files=$(cnt '*.tsx' '*.jsx' '*.vue' '*.svelte')"

deps=$(list0 "${MANIFESTS[@]}" | xargs -0 cat 2>/dev/null | tr 'A-Z' 'a-z')
# Пакет по имени: "name" в package.json, name== / "name>= / name = в Python-манифестах.
has() { local re="(^|\")($1)(\"|[=<>~!\[ ;]|\$)"
  printf '%s\n' "$deps" | grep -oE "$re" | sed -E "s#$re#\2#" | sort -u | tr '\n' ',' | sed 's/,$//'; }
anyfile() { [ "$(list "$@" | head -1)" ] && echo yes || echo no; }

web=$(has 'express|fastify|koa|hono|@nestjs/core|next|nuxt|@remix-run/node|stripe|passport|jsonwebtoken|django|flask|fastapi|spring-boot-starter-web|laravel/framework|gin-gonic/gin|actix-web|axum')
ui=$(has 'react|vue|svelte|@angular/core|solid-js|next|nuxt|tailwindcss')
bots=$(has 'grammy|telegraf|node-telegram-bot-api|discord\.js|@slack/bolt|aiogram|python-telegram-bot|pytelegrambotapi|telethon|pyrogram|discord\.py|nextcord|py-cord|slack-bolt')
agents=$(has '@anthropic-ai/claude-agent-sdk|@anthropic-ai/sdk|claude-agent-sdk|anthropic|openai|langchain|@langchain/core|langgraph|@langchain/langgraph|crewai|pydantic-ai|ai|@mastra/core|@modelcontextprotocol/sdk|mcp')
crypto=$(has 'ethers|viem|web3|wagmi|hardhat|@openzeppelin/contracts|@solana/web3\.js|@coral-xyz/anchor|anchor-lang|solana-program|solana|solders|@ton/core|@ton/ton|tonweb|tonsdk|pytonlib|@cosmjs/stargate|cosmwasm-std')
[ "$(anyfile 'foundry.toml' '*/foundry.toml' 'hardhat.config.*' 'Anchor.toml' '*.sol' '*.fc' '*.tact' '*.cairo' '*.move')" = yes ] && crypto="${crypto:+$crypto,}contracts"
engine=none
[ "$(anyfile 'project.godot' '*/project.godot')" = yes ] && engine=godot
[ "$(anyfile 'ProjectSettings/ProjectVersion.txt' '*/ProjectSettings/ProjectVersion.txt')" = yes ] && engine=unity
[ "$(anyfile '*.uproject')" = yes ] && engine=unreal

echo "web: ${web:-none}"
echo "ui: ${ui:-none}"
echo "bots: ${bots:-none}"
echo "agents: ${agents:-none}"
echo "crypto: ${crypto:-none}"
echo "engine: $engine"

b() { command -v "$1" >/dev/null 2>&1 && echo yes || echo no; }
py=no; { command -v python3 || command -v python; } >/dev/null 2>&1 && py=yes
echo "bin: claude=$(b claude) node=$(b node) npm=$(b npm) python=$py" \
     "typescript-language-server=$(b typescript-language-server) pyright-langserver=$(b pyright-langserver)" \
     "gopls=$(b gopls) rust-analyzer=$(b rust-analyzer) csharp-ls=$(b csharp-ls)" \
     "intelephense=$(b intelephense) clangd=$(b clangd) jdtls=$(b jdtls)"
