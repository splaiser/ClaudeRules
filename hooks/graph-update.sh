#!/bin/bash
# Stop: обновить graphify один раз за ход и только если были правки.
cat >/dev/null
m="${TMPDIR:-/tmp}/claude-graph-$(printf %s "$CLAUDE_PROJECT_DIR" | cksum | cut -d' ' -f1)"
[ -f "$m" ] || exit 0
rm -f "$m"
cd "$CLAUDE_PROJECT_DIR" && command -v graphify >/dev/null && graphify update . >/dev/null 2>&1
exit 0
