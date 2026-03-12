#!/usr/bin/env bash
# sessionEnd hook — finalize session: summary, transcript commit, cleanup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/audit-common.sh"

init_audit

REASON=$(echo "$INPUT" | jq -r '.reason // "unknown"')

SDIR=$(session_dir)
mkdir -p "$SDIR"

# Append sessionEnd to transcript
TRANSCRIPT_ENTRY=$(jq -nc \
  --arg type "sessionEnd" \
  --arg reason "$REASON" \
  --argjson timestamp "${TIMESTAMP:-0}" \
  '{type: $type, reason: $reason, timestamp: $timestamp}')
append_transcript "$TRANSCRIPT_ENTRY"

# Write session-end summary
COUNTER=$(next_counter)
FILENAME="${COUNTER}-session-end.md"
TRANSCRIPT_FILE="$SDIR/session-transcript.jsonl"

TOOL_COUNT=0
ERROR_COUNT=0
PROMPT_COUNT=0
if [[ -f "$TRANSCRIPT_FILE" ]]; then
  TOOL_COUNT=$(grep -c '"type":"toolResult"' "$TRANSCRIPT_FILE" 2>/dev/null || echo 0)
  ERROR_COUNT=$(grep -c '"type":"error"' "$TRANSCRIPT_FILE" 2>/dev/null || echo 0)
  PROMPT_COUNT=$(grep -c '"type":"userPrompt"' "$TRANSCRIPT_FILE" 2>/dev/null || echo 0)
fi

cat > "$SDIR/$FILENAME" <<EOF
# Session End: $SESSION_ID

- **Reason**: $REASON
- **Timestamp**: $TIMESTAMP
- **Prompts**: $PROMPT_COUNT
- **Tool uses**: $TOOL_COUNT
- **Errors**: $ERROR_COUNT
EOF

# Commit transcript and summary together
git -C "$AUDIT_REPO" add -- "sessions/$SESSION_ID/session-transcript.jsonl" 2>/dev/null || true
git -C "$AUDIT_REPO" add -- "sessions/$SESSION_ID/$FILENAME" 2>/dev/null || true
audit_commit "sessions/$SESSION_ID/$FILENAME" \
  "[$SESSION_ID] session end: $REASON"

# Cleanup temp session ID file
cleanup_session_id

# Auto-push if configured
if [[ "$AUDIT_PUSH" == "true" ]]; then
  if [[ "$AUDIT_MODE" == "per-session" ]]; then
    git -C "$AUDIT_REPO" push origin "session/$SESSION_ID" --quiet 2>/dev/null || true
  else
    git -C "$AUDIT_REPO" push origin "$AUDIT_BRANCH" --quiet 2>/dev/null || true
  fi
fi
