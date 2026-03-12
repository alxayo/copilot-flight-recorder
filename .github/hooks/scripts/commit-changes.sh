#!/usr/bin/env bash
# postToolUse hook — capture workspace diff and tool results after file-editing tools
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/audit-common.sh"

init_audit

TOOL_NAME=$(json_field "toolName")
TOOL_ARGS_RAW=$(json_field "toolArgs")
RESULT_TYPE=$(echo "$INPUT" | jq -r '.toolResult.resultType // empty')
RESULT_TEXT=$(echo "$INPUT" | jq -r '.toolResult.textResultForLlm // empty')

# File-editing tools that should trigger diff capture
FILE_EDIT_TOOLS="edit create bash"
MATCH=false
for tool in $FILE_EDIT_TOOLS; do
  if [[ "$TOOL_NAME" == "$tool" ]]; then
    MATCH=true
    break
  fi
done

# Non-editing tools: skip diff but still log tool result to transcript
if [[ "$MATCH" != "true" ]]; then
  # Append tool result to transcript even for non-editing tools
  TRANSCRIPT_ENTRY=$(jq -nc \
    --arg type "toolResult" \
    --arg toolName "$TOOL_NAME" \
    --arg resultType "$RESULT_TYPE" \
    --arg textResultForLlm "$RESULT_TEXT" \
    --argjson timestamp "${TIMESTAMP:-0}" \
    '{type: $type, toolName: $toolName, resultType: $resultType, textResultForLlm: $textResultForLlm, timestamp: $timestamp}')
  append_transcript "$TRANSCRIPT_ENTRY"
  exit 0
fi

# Parse toolArgs to extract file path
FILE_PATH=""
if [[ -n "$TOOL_ARGS_RAW" ]]; then
  FILE_PATH=$(echo "$TOOL_ARGS_RAW" | jq -r 'fromjson | .path // .filePath // empty' 2>/dev/null || true)
fi

# Capture workspace diff (tracked files: staged + unstaged vs HEAD)
DIFF=""
if [[ -n "$HOOK_CWD" ]] && [[ -d "$HOOK_CWD/.git" ]]; then
  DIFF=$(git -C "$HOOK_CWD" diff HEAD 2>/dev/null || git -C "$HOOK_CWD" diff 2>/dev/null || true)
fi

# For new/untracked files (e.g. create), capture content directly
if [[ -z "$DIFF" ]] && [[ -n "$FILE_PATH" ]] && [[ -f "$FILE_PATH" ]]; then
  DIFF="new file: ${FILE_PATH}
---
$(cat "$FILE_PATH")"
fi

SDIR=$(session_dir)
mkdir -p "$SDIR"

# For bash tool, skip patch if diff is empty (read-only command)
if [[ "$TOOL_NAME" == "bash" ]] && [[ -z "$DIFF" ]]; then
  # Still write tool result and transcript entry
  COUNTER=$(next_counter)
  RESULT_FILENAME="${COUNTER}-tool-result.json"

  jq -n \
    --arg sessionId "$SESSION_ID" \
    --arg toolName "$TOOL_NAME" \
    --arg resultType "$RESULT_TYPE" \
    --arg textResultForLlm "$RESULT_TEXT" \
    --argjson timestamp "${TIMESTAMP:-0}" \
    '{
      sessionId: $sessionId,
      toolName: $toolName,
      resultType: $resultType,
      textResultForLlm: $textResultForLlm,
      timestamp: $timestamp
    }' > "$SDIR/$RESULT_FILENAME"

  TRANSCRIPT_ENTRY=$(jq -nc \
    --arg type "toolResult" \
    --arg toolName "$TOOL_NAME" \
    --arg resultType "$RESULT_TYPE" \
    --arg textResultForLlm "$RESULT_TEXT" \
    --argjson timestamp "${TIMESTAMP:-0}" \
    '{type: $type, toolName: $toolName, resultType: $resultType, textResultForLlm: $textResultForLlm, timestamp: $timestamp}')
  append_transcript "$TRANSCRIPT_ENTRY"

  audit_commit "sessions/$SESSION_ID/$RESULT_FILENAME" \
    "[$SESSION_ID] tool result: $TOOL_NAME (no changes)"
  exit 0
fi

# Nothing changed and not bash — skip entirely
if [[ -z "$DIFF" ]]; then
  TRANSCRIPT_ENTRY=$(jq -nc \
    --arg type "toolResult" \
    --arg toolName "$TOOL_NAME" \
    --arg resultType "$RESULT_TYPE" \
    --arg textResultForLlm "$RESULT_TEXT" \
    --argjson timestamp "${TIMESTAMP:-0}" \
    '{type: $type, toolName: $toolName, resultType: $resultType, textResultForLlm: $textResultForLlm, timestamp: $timestamp}')
  append_transcript "$TRANSCRIPT_ENTRY"
  exit 0
fi

COUNTER=$(next_counter)
PATCH_FILENAME="${COUNTER}-changes.patch"
META_FILENAME="${COUNTER}-changes.meta.json"
RESULT_FILENAME="${COUNTER}-tool-result.json"

echo "$DIFF" > "$SDIR/$PATCH_FILENAME"

# Build metadata sidecar for cross-referencing audit repo ↔ source repo
WORKSPACE_HEAD=""
FILE_CONTENT_HASH="null"
if [[ -n "$HOOK_CWD" ]] && [[ -d "$HOOK_CWD/.git" ]]; then
  WORKSPACE_HEAD=$(git -C "$HOOK_CWD" rev-parse HEAD 2>/dev/null || echo "")
fi
if [[ -n "$FILE_PATH" ]] && [[ -f "$FILE_PATH" ]]; then
  FILE_CONTENT_HASH=$(git hash-object "$FILE_PATH" 2>/dev/null || echo "null")
fi

jq -n \
  --arg sessionId  "$SESSION_ID" \
  --arg filePath    "${FILE_PATH:-unknown}" \
  --arg wsHead      "$WORKSPACE_HEAD" \
  --arg contentHash "$FILE_CONTENT_HASH" \
  --argjson timestamp "${TIMESTAMP:-0}" \
  --arg toolName    "$TOOL_NAME" \
  --arg patchFile   "$PATCH_FILENAME" \
  '{
    sessionId:       $sessionId,
    filePath:        $filePath,
    workspaceHead:   $wsHead,
    fileContentHash: (if $contentHash == "null" then null else $contentHash end),
    timestamp:       $timestamp,
    toolName:        $toolName,
    patchFile:       $patchFile
  }' > "$SDIR/$META_FILENAME"

# Write tool result
jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg toolName "$TOOL_NAME" \
  --arg resultType "$RESULT_TYPE" \
  --arg textResultForLlm "$RESULT_TEXT" \
  --argjson timestamp "${TIMESTAMP:-0}" \
  '{
    sessionId: $sessionId,
    toolName: $toolName,
    resultType: $resultType,
    textResultForLlm: $textResultForLlm,
    timestamp: $timestamp
  }' > "$SDIR/$RESULT_FILENAME"

# Append tool result to transcript
TRANSCRIPT_ENTRY=$(jq -nc \
  --arg type "toolResult" \
  --arg toolName "$TOOL_NAME" \
  --arg resultType "$RESULT_TYPE" \
  --arg textResultForLlm "$RESULT_TEXT" \
  --argjson timestamp "${TIMESTAMP:-0}" \
  '{type: $type, toolName: $toolName, resultType: $resultType, textResultForLlm: $textResultForLlm, timestamp: $timestamp}')
append_transcript "$TRANSCRIPT_ENTRY"

SHORT_FILE=$(basename "${FILE_PATH:-unknown}")
git -C "$AUDIT_REPO" add -- "sessions/$SESSION_ID/$META_FILENAME"
git -C "$AUDIT_REPO" add -- "sessions/$SESSION_ID/$RESULT_FILENAME"
audit_commit "sessions/$SESSION_ID/$PATCH_FILENAME" \
  "[$SESSION_ID] changes: $TOOL_NAME on $SHORT_FILE"
