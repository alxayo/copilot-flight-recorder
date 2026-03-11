#!/usr/bin/env bash
# UserPromptSubmit hook — capture the user's prompt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/audit-common.sh"

init_audit

PROMPT=$(json_field "prompt")

# Nothing to capture if prompt is empty
if [[ -z "$PROMPT" ]]; then
  exit 0
fi

SDIR=$(session_dir)
mkdir -p "$SDIR"

COUNTER=$(next_counter)
FILENAME="${COUNTER}-prompt.md"

{
  echo "# User Prompt"
  echo ""
  echo "$PROMPT"
} > "$SDIR/$FILENAME"

# Truncate prompt for the commit message
SHORT_PROMPT="${PROMPT:0:50}"

audit_commit "sessions/$SESSION_ID/$FILENAME" \
  "[$SESSION_ID] prompt: $SHORT_PROMPT"
