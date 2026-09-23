#!/bin/bash
# Замер размера проекта для решения «ставить graphify или нет».
# Пороги — эвристика, правь под себя.
FILES_BIG=150        # файлов кода
LINES_BIG=20000      # строк кода
DOCS_KB_BIG=150      # документы (md/pdf/docx/txt), ~40 тыс. токенов
FILES_MID=50

CODE=('*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.py' '*.go' '*.rs' '*.java' '*.kt'
      '*.cs' '*.rb' '*.php' '*.swift' '*.c' '*.cpp' '*.h' '*.vue' '*.svelte' '*.sql'
      '*.bsl' '*.os')
SKIP=(':!:*.min.*' ':!:*/dist/*' ':!:*/build/*' ':!:*/vendor/*' ':!:*/node_modules/*')
DOCS=('*.md' '*.mdx' '*.pdf' '*.docx' '*.txt')

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  files=$(git ls-files -- "${CODE[@]}" "${SKIP[@]}" | wc -l)
  lines=$(git ls-files -z -- "${CODE[@]}" "${SKIP[@]}" | xargs -0 cat 2>/dev/null | wc -l)
  docs=$(git ls-files -z -- "${DOCS[@]}" "${SKIP[@]}" | xargs -0 cat 2>/dev/null | wc -c)
else
  echo "note: не git-репозиторий, замер по find (менее точный)"
  prune='-path */node_modules -o -path */.git -o -path */dist -o -path */build -o -path */vendor'
  names=$(printf -- "-name %s -o " "${CODE[@]}"); names="${names% -o }"
  files=$(eval "find . \\( $prune \\) -prune -o -type f \\( $names \\) -print" | wc -l)
  lines=$(eval "find . \\( $prune \\) -prune -o -type f \\( $names \\) -print0" | xargs -0 cat 2>/dev/null | wc -l)
  dn=$(printf -- "-name %s -o " "${DOCS[@]}"); dn="${dn% -o }"
  docs=$(eval "find . \\( $prune \\) -prune -o -type f \\( $dn \\) -print0" | xargs -0 cat 2>/dev/null | wc -c)
fi
docs_kb=$((docs / 1024))

if [ "$files" -ge "$FILES_BIG" ] || [ "$lines" -ge "$LINES_BIG" ]; then verdict=LARGE_CODE
elif [ "$docs_kb" -ge "$DOCS_KB_BIG" ]; then verdict=LARGE_DOCS
elif [ "$files" -ge "$FILES_MID" ]; then verdict=BORDERLINE
else verdict=SMALL; fi

echo "files=$files lines=$lines docs_kb=$docs_kb verdict=$verdict"
