#!/usr/bin/env bash
# PostToolUse hook — capture workspace diff after file-editing tools
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/audit-common.sh"

init_audit

TOOL_NAME=$(json_field "tool_name")

# Only act on file-editing tools; silently skip everything else.
FILE_EDIT_TOOLS="create_file replace_string_in_file multi_replace_string_in_file edit_notebook_file insert_text_in_file delete_file"
MATCH=false
for tool in $FILE_EDIT_TOOLS; do
  if [[ "$TOOL_NAME" == "$tool" ]]; then
    MATCH=true
    break
  fi
done

if [[ "$MATCH" != "true" ]]; then
  exit 0
fi

# Determine the affected file path from tool_input
FILE_PATH=""
case "$TOOL_NAME" in
  multi_replace_string_in_file)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.replacements[0].filePath // empty')
    ;;
  *)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.filePath // empty')
    ;;
esac

# Capture workspace diff (tracked files: staged + unstaged vs HEAD)
DIFF=""
if [[ -n "$HOOK_CWD" ]] && [[ -d "$HOOK_CWD/.git" ]]; then
  DIFF=$(git -C "$HOOK_CWD" diff HEAD 2>/dev/null || git -C "$HOOK_CWD" diff 2>/dev/null || true)
fi

# For new/untracked files (e.g. create_file), capture content directly
if [[ -z "$DIFF" ]] && [[ -n "$FILE_PATH" ]] && [[ -f "$FILE_PATH" ]]; then
  DIFF="new file: ${FILE_PATH}
---
$(cat "$FILE_PATH")"
fi

# Nothing changed — skip
if [[ -z "$DIFF" ]]; then
  exit 0
fi

SDIR=$(session_dir)
mkdir -p "$SDIR"

COUNTER=$(next_counter)
FILENAME="${COUNTER}-changes.patch"

echo "$DIFF" > "$SDIR/$FILENAME"

SHORT_FILE=$(basename "${FILE_PATH:-unknown}")
audit_commit "sessions/$SESSION_ID/$FILENAME" \
  "[$SESSION_ID] changes: $TOOL_NAME on $SHORT_FILE"
