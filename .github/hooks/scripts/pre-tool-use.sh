#!/usr/bin/env bash
# preToolUse hook — log tool invocation intent before execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/audit-common.sh"

init_audit

TOOL_NAME=$(json_field "toolName")
TOOL_ARGS_RAW=$(json_field "toolArgs")

# Parse toolArgs JSON string gracefully; fall back to raw string on failure
TOOL_ARGS_PARSED=""
if [[ -n "$TOOL_ARGS_RAW" ]]; then
  TOOL_ARGS_PARSED=$(echo "$TOOL_ARGS_RAW" | jq '.' 2>/dev/null || echo "$TOOL_ARGS_RAW")
fi

SDIR=$(session_dir)
mkdir -p "$SDIR"

COUNTER=$(next_counter)
FILENAME="${COUNTER}-tool-attempt.json"

jq -n \
  --arg toolName "$TOOL_NAME" \
  --argjson toolArgs "$( echo "$TOOL_ARGS_PARSED" | jq '.' 2>/dev/null || jq -n --arg s "$TOOL_ARGS_RAW" '$s' )" \
  --argjson timestamp "${TIMESTAMP:-0}" \
  --arg sessionId "$SESSION_ID" \
  '{
    sessionId: $sessionId,
    toolName: $toolName,
    toolArgs: $toolArgs,
    timestamp: $timestamp
  }' > "$SDIR/$FILENAME"

# Append to transcript
TRANSCRIPT_ENTRY=$(jq -nc \
  --arg type "toolAttempt" \
  --arg toolName "$TOOL_NAME" \
  --arg toolArgs "$TOOL_ARGS_RAW" \
  --argjson timestamp "${TIMESTAMP:-0}" \
  '{type: $type, toolName: $toolName, toolArgs: $toolArgs, timestamp: $timestamp}')
append_transcript "$TRANSCRIPT_ENTRY"

audit_commit "sessions/$SESSION_ID/$FILENAME" \
  "[$SESSION_ID] tool attempt: $TOOL_NAME"

# Exit 0 to allow tool execution (no deny by default)
exit 0
