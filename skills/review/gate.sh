#!/bin/bash
# Нужен ли reviewer и на какой дифф. Считается только новое с прошлого ревью этой ветки.
# Состояние — в .git (в коммиты не попадает), журнал ревью — ~/.claude/review-log.tsv.
#   gate.sh                    оценить изменения с прошлого ревью
#   gate.sh --base <ref>       оценить изменения от явной базы (коммит, ветка)
#   gate.sh --start            точка отсчёта задачи, если истории ревью в ветке ещё нет
#   gate.sh --mark ok|findings после ответа reviewer: проверенный снимок становится базой
#   gate.sh --reset            забыть историю ревью ветки
# Пороги и зоны риска — эвристика, правь под себя.
SKIP_LINES=20   # без ревью: значимых строк (добавленные + удалённые) не больше SKIP_LINES,
SKIP_FILES=1    # файлов кода не больше SKIP_FILES и ничего из зон риска
BIG_LINES=400; BIG_FILES=15
DOCS_RE='(\.(md|mdx|txt|rst|adoc)$|(^|/)docs/)'
LOCK_RE='(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?|poetry\.lock|uv\.lock|Pipfile\.lock|Cargo\.lock|go\.sum|composer\.lock|Gemfile\.lock)$'
DEPS_RE='(^|/)(package\.json|pyproject\.toml|requirements[^/]*\.txt|Pipfile|go\.mod|Cargo\.toml|composer\.json|Gemfile|pom\.xml|build\.gradle(\.kts)?)$'
RISK_RE='auth|login|session|passw|permission|acl|role|payment|billing|invoice|checkout|price|wallet|keypair|private[_-]?key|api[_-]?key|secret|crypt|signature|signer|migration|schema|\.sql$|\.(sol|move|cairo|fc|tact)$|(^|/)\.github/workflows/|dockerfile|docker-compose|deploy|\.env'

set -euo pipefail
root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "verdict: run"; echo "reason: не git-репозиторий — дельту посчитать нельзя"; exit 0; }
cd "$root"
gitdir=$(git rev-parse --absolute-git-dir)
branch=$(git symbolic-ref --short -q HEAD || echo detached)
state="$gitdir/claude-review/${branch//\//__}"
log="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/review-log.tsv"
project="$(basename "$root")-$(printf %s "$root" | git hash-object --stdin | cut -c1-8)"
EMPTY_TREE=$(git hash-object -t tree /dev/null)

get() { [ -f "$state" ] && sed -n "s/^$1=//p" "$state" || true; }
put() { mkdir -p "$(dirname "$state")"
  { grep -v "^$1=" "$state" 2>/dev/null || true; echo "$1=$2"; } > "$state.tmp"; mv "$state.tmp" "$state"; }
exists() { [ -n "$1" ] && git cat-file -e "$1" 2>/dev/null; }

snapshot() {  # дерево рабочей копии с неотслеживаемыми файлами; настоящий индекс не трогается
  local idx; idx=$(mktemp -u)
  [ -f "$gitdir/index" ] && cp "$gitdir/index" "$idx"
  GIT_INDEX_FILE="$idx" git add -A . >/dev/null 2>&1
  GIT_INDEX_FILE="$idx" git write-tree; rm -f "$idx"
}

default_base() {  # истории нет: ветка от основной — вся ветка; иначе — незакоммиченное
  local head main mb
  head=$(git rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null) || { echo "$EMPTY_TREE"; return; }
  main=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null ||
    { git rev-parse -q --verify main >/dev/null && echo main; } ||
    { git rev-parse -q --verify master >/dev/null && echo master; } || true)
  if [ -n "$main" ] && mb=$(git merge-base HEAD "$main" 2>/dev/null) &&
     [ "$mb" != "$(git rev-parse HEAD)" ]; then git rev-parse "$mb^{tree}"; else echo "$head"; fi
}

case "${1:-}" in
  --reset) rm -f "$state"; echo "история ревью ветки $branch сброшена"; exit 0 ;;
  --start) exists "$(get reviewed)" && { echo "история есть — точка отсчёта не нужна"; exit 0; }
           put reviewed "$(snapshot)"; echo "точка отсчёта задачи записана"; exit 0 ;;
  --mark)  res="${2:?укажи результат: ok или findings}"; cur=$(get pending)
           exists "$cur" || { echo "нет снимка — сначала gate.sh" >&2; exit 1; }
           put reviewed "$cur"; mkdir -p "$(dirname "$log")"
           printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$project" "$branch" "$(get stats)" "$res" >> "$log"
           echo "отмечено как проверенное: ${cur:0:12}"; exit 0 ;;
  --base)  base=$(git rev-parse "${2:?укажи базу}^{tree}") ;;
  "")      base=$(get reviewed); exists "$base" || base=$(default_base) ;;
  *)       echo "неизвестный аргумент: $1" >&2; exit 2 ;;
esac

cur=$(snapshot); put pending "$cur"
out() { echo "verdict: $1"; echo "reason: $2"; echo "base: $base"; echo "current: $cur"
  echo "diff: git diff $base $cur"; [ -z "$stats" ] || echo "stats: $stats"
  [ -z "$focus" ] || echo "focus: $focus"; }
stats=""; focus=""
[ "$base" = "$cur" ] && { out skip "нет изменений с прошлого ревью"; exit 0; }

code_files=0; code_lines=0; other=0; deps=no; all_files=0
while IFS=$'\t' read -r a d path; do
  all_files=$((all_files + 1))
  if printf '%s' "$path" | grep -qiE "$DOCS_RE|$LOCK_RE"; then other=$((other + 1)); continue; fi
  printf '%s' "$path" | grep -qE "$DEPS_RE" && deps=yes
  printf '%s' "$path" | grep -qiE "$RISK_RE" && focus="${focus:+$focus, }$path"
  code_files=$((code_files + 1))
  [ "$a" = - ] || code_lines=$((code_lines + a + d))
done < <(git diff --no-renames --numstat "$base" "$cur")

# Значимые строки — без изменений только в пробелах и пустых строках.
sig_lines=0
while IFS=$'\t' read -r a d path; do
  printf '%s' "$path" | grep -qiE "$DOCS_RE|$LOCK_RE" && continue
  [ "$a" = - ] || sig_lines=$((sig_lines + a + d))
done < <(git diff --no-renames --numstat -w --ignore-blank-lines "$base" "$cur")

size=normal
{ [ "$sig_lines" -ge "$BIG_LINES" ] || [ "$code_files" -ge "$BIG_FILES" ]; } && size=big
stats="code_files=$code_files code_lines=$sig_lines raw_lines=$code_lines other_files=$other deps=$deps size=$size"
put stats "$stats risk=$([ -n "$focus" ] && echo yes || echo no)"

if [ "$code_files" -eq 0 ]; then out skip "только документация и lock-файлы"
elif [ "$sig_lines" -eq 0 ] && [ -z "$focus" ]; then out skip "только пробелы и пустые строки"
elif [ -n "$focus" ]; then out run "затронуты зоны риска"
elif [ "$deps" = yes ]; then out run "изменены зависимости"
elif [ "$sig_lines" -le "$SKIP_LINES" ] && [ "$code_files" -le "$SKIP_FILES" ]; then
  out skip "мелкая правка: строк $sig_lines, файлов $code_files — копится до следующего ревью"
else out run "значимых строк $sig_lines, файлов $code_files"; fi
