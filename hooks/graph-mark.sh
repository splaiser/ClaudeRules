#!/bin/bash
# PostToolUse(Edit|Write|MultiEdit): отметить правки в проекте с графом graphify.
cat >/dev/null
[ -d "$CLAUDE_PROJECT_DIR/graphify-out" ] || exit 0
touch "${TMPDIR:-/tmp}/claude-graph-$(printf %s "$CLAUDE_PROJECT_DIR" | cksum | cut -d' ' -f1)"
exit 0
