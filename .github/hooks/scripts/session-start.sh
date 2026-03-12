#!/usr/bin/env bash
# sessionStart hook — initialise the CLI audit session
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/audit-common.sh"

init_audit_session_start

SDIR=$(session_dir)
mkdir -p "$SDIR"

# Initialise the monotonic counter for this session
echo "0" > "$SDIR/.counter"

SOURCE=$(json_field "source")
INITIAL_PROMPT=$(json_field "initialPrompt")
COUNTER=$(next_counter)
FILENAME="${COUNTER}-session-start.md"

{
  echo "# Session Start"
  echo ""
  echo "- **Session ID**: ${SESSION_ID}"
  echo "- **Timestamp**: ${TIMESTAMP}"
  echo "- **Workspace**: ${HOOK_CWD}"
  echo "- **Source**: ${SOURCE:-new}"
  echo "- **Mode**: ${AUDIT_MODE}"
  if [[ -n "$INITIAL_PROMPT" ]]; then
    echo ""
    echo "## Initial Prompt"
    echo ""
    echo "$INITIAL_PROMPT"
  fi
} > "$SDIR/$FILENAME"

# Initialize transcript with session start entry
TRANSCRIPT_ENTRY=$(jq -nc \
  --arg type "sessionStart" \
  --arg source "${SOURCE:-new}" \
  --arg initialPrompt "$INITIAL_PROMPT" \
  --argjson timestamp "${TIMESTAMP:-0}" \
  '{type: $type, source: $source, initialPrompt: $initialPrompt, timestamp: $timestamp}')
append_transcript "$TRANSCRIPT_ENTRY"

audit_commit "sessions/$SESSION_ID/$FILENAME" \
  "[$SESSION_ID] session start"
