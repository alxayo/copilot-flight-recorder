#!/usr/bin/env bash
# SessionStart hook — initialise the audit session
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/audit-common.sh"

init_audit

SDIR=$(session_dir)
mkdir -p "$SDIR"

# Initialise the monotonic counter for this session
echo "0" > "$SDIR/.counter"

SOURCE=$(json_field "source")
COUNTER=$(next_counter)
FILENAME="${COUNTER}-session-start.md"

cat > "$SDIR/$FILENAME" << EOF
# Session Start

- **Session ID**: ${SESSION_ID}
- **Timestamp**: ${TIMESTAMP}
- **Workspace**: ${HOOK_CWD}
- **Source**: ${SOURCE:-new}
- **Mode**: ${AUDIT_MODE}
EOF

audit_commit "sessions/$SESSION_ID/$FILENAME" \
  "[$SESSION_ID] session start"
