#!/usr/bin/env bash
# Stop hook — copy transcript and finalise the audit session
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/audit-common.sh"

init_audit

SDIR=$(session_dir)
mkdir -p "$SDIR"

# Copy full transcript if the path was provided and the file exists
if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
  cp "$TRANSCRIPT_PATH" "$SDIR/transcript.json"
  audit_commit "sessions/$SESSION_ID/transcript.json" \
    "[$SESSION_ID] transcript: session complete"
fi

# Auto-push if configured
if [[ "$AUDIT_PUSH" == "true" ]]; then
  if [[ "$AUDIT_MODE" == "per-session" ]]; then
    git -C "$AUDIT_REPO" push origin "session/$SESSION_ID" --quiet 2>/dev/null || true
  else
    git -C "$AUDIT_REPO" push origin "$AUDIT_BRANCH" --quiet 2>/dev/null || true
  fi
fi
