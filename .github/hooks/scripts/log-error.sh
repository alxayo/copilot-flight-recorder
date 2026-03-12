#!/usr/bin/env bash
# errorOccurred hook — log errors during agent execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/audit-common.sh"

init_audit

ERROR_MESSAGE=$(echo "$INPUT" | jq -r '.error.message // empty')
ERROR_NAME=$(echo "$INPUT" | jq -r '.error.name // empty')
ERROR_STACK=$(echo "$INPUT" | jq -r '.error.stack // empty')

SDIR=$(session_dir)
mkdir -p "$SDIR"

COUNTER=$(next_counter)
FILENAME="${COUNTER}-error.json"

jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg errorName "$ERROR_NAME" \
  --arg errorMessage "$ERROR_MESSAGE" \
  --arg errorStack "$ERROR_STACK" \
  --argjson timestamp "${TIMESTAMP:-0}" \
  '{
    sessionId: $sessionId,
    error: {
      name: $errorName,
      message: $errorMessage,
      stack: $errorStack
    },
    timestamp: $timestamp
  }' > "$SDIR/$FILENAME"

# Append to transcript
ERROR_OBJ=$(echo "$INPUT" | jq -c '.error // {}')
TRANSCRIPT_ENTRY=$(jq -nc \
  --arg type "error" \
  --argjson error "$ERROR_OBJ" \
  --argjson timestamp "${TIMESTAMP:-0}" \
  '{type: $type, error: $error, timestamp: $timestamp}')
append_transcript "$TRANSCRIPT_ENTRY"

SHORT_ERROR="${ERROR_MESSAGE:0:50}"
audit_commit "sessions/$SESSION_ID/$FILENAME" \
  "[$SESSION_ID] error: $SHORT_ERROR"
