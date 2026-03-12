#!/usr/bin/env bash
# Shared utilities for Copilot CLI Audit Hooks (Bash/Linux/macOS)
set -euo pipefail

AUDIT_REPO=""
AUDIT_MODE="flat"
AUDIT_BRANCH="main"
AUDIT_PUSH="false"

INPUT=""
SESSION_ID=""
HOOK_CWD=""
TIMESTAMP=""

# ---------------------------------------------------------------------------
# Read JSON from stdin and extract common fields
# CLI payloads have: timestamp (Unix ms), cwd. No session_id or transcript_path.
# ---------------------------------------------------------------------------
read_input() {
  INPUT=$(cat)
  HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  TIMESTAMP=$(echo "$INPUT" | jq -r '.timestamp // empty')
}

# Extract a single field from the stored INPUT JSON
json_field() {
  echo "$INPUT" | jq -r ".$1 // empty"
}

# ---------------------------------------------------------------------------
# Load configuration: environment variables → .env file → defaults
# Environment variables always take priority over .env values.
# ---------------------------------------------------------------------------
load_config() {
  local env_file="${HOOK_CWD:-.}/.env"
  if [[ -f "$env_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Skip comments and blank lines
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue

      local key value
      key="${line%%=*}"
      value="${line#*=}"
      # Trim whitespace
      key="$(echo "$key" | tr -d '[:space:]')"
      # Remove surrounding quotes from value
      value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      value="${value#\"}" ; value="${value%\"}"
      value="${value#\'}" ; value="${value%\'}"

      case "$key" in
        COPILOT_AUDIT_REPO)   [[ -z "${COPILOT_AUDIT_REPO:-}" ]]   && export COPILOT_AUDIT_REPO="$value" ;;
        COPILOT_AUDIT_MODE)   [[ -z "${COPILOT_AUDIT_MODE:-}" ]]   && export COPILOT_AUDIT_MODE="$value" ;;
        COPILOT_AUDIT_BRANCH) [[ -z "${COPILOT_AUDIT_BRANCH:-}" ]] && export COPILOT_AUDIT_BRANCH="$value" ;;
        COPILOT_AUDIT_PUSH)   [[ -z "${COPILOT_AUDIT_PUSH:-}" ]]   && export COPILOT_AUDIT_PUSH="$value" ;;
      esac
    done < "$env_file"
  fi

  AUDIT_REPO="${COPILOT_AUDIT_REPO:-}"
  AUDIT_MODE="${COPILOT_AUDIT_MODE:-flat}"
  AUDIT_BRANCH="${COPILOT_AUDIT_BRANCH:-main}"
  AUDIT_PUSH="${COPILOT_AUDIT_PUSH:-false}"

  if [[ -z "$AUDIT_REPO" ]]; then
    echo "ERROR: COPILOT_AUDIT_REPO is not set. Set it as an environment variable or in .env" >&2
    exit 2
  fi

  if [[ ! -d "$AUDIT_REPO/.git" ]]; then
    echo "ERROR: $AUDIT_REPO is not a git repository" >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Session ID synthesis
# CLI provides no session_id. We synthesize one at sessionStart and persist
# it in a temp file keyed by cwd hash + parent PID.
# ---------------------------------------------------------------------------
cwd_hash() {
  echo -n "${HOOK_CWD:-unknown}" | md5sum | cut -c1-8
}

session_id_file() {
  local hash
  hash=$(cwd_hash)
  echo "/tmp/copilot-audit-${hash}-${PPID}"
}

generate_session_id() {
  local datestamp
  datestamp=$(date -u +"%Y%m%d-%H%M%S")
  local hash
  hash=$(cwd_hash)
  SESSION_ID="cli-${datestamp}-${hash}"
  echo "$SESSION_ID" > "$(session_id_file)"
}

read_session_id() {
  local id_file
  id_file=$(session_id_file)
  if [[ -f "$id_file" ]]; then
    SESSION_ID=$(cat "$id_file")
  else
    echo "ERROR: No session ID file found at $id_file. Was sessionStart called?" >&2
    exit 2
  fi
}

cleanup_session_id() {
  local id_file
  id_file=$(session_id_file)
  rm -f "$id_file"
}

# ---------------------------------------------------------------------------
# Session directory path inside the audit repo
# ---------------------------------------------------------------------------
session_dir() {
  echo "$AUDIT_REPO/sessions/$SESSION_ID"
}

# ---------------------------------------------------------------------------
# Get and increment the monotonic counter for this session (zero-padded 3 digits)
# ---------------------------------------------------------------------------
next_counter() {
  local sdir
  sdir="$(session_dir)"
  local counter_file="$sdir/.counter"
  local counter=0
  if [[ -f "$counter_file" ]]; then
    counter=$(cat "$counter_file")
  fi
  counter=$((counter + 1))
  echo "$counter" > "$counter_file"
  printf "%03d" "$counter"
}

# ---------------------------------------------------------------------------
# Ensure the target branch is checked out in the audit repo
# ---------------------------------------------------------------------------
ensure_branch() {
  local branch="$1"
  local current
  current=$(git -C "$AUDIT_REPO" branch --show-current 2>/dev/null || echo "")

  if [[ "$current" == "$branch" ]]; then
    return
  fi

  if git -C "$AUDIT_REPO" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    git -C "$AUDIT_REPO" checkout "$branch" --quiet
  else
    git -C "$AUDIT_REPO" checkout -b "$branch" --quiet
  fi
}

# ---------------------------------------------------------------------------
# Stage a file and commit it to the audit repo
# ---------------------------------------------------------------------------
audit_commit() {
  local file_path="$1"  # relative to audit repo root
  local message="$2"

  git -C "$AUDIT_REPO" add -- "$file_path"
  GIT_AUTHOR_NAME="copilot-audit" \
  GIT_AUTHOR_EMAIL="copilot-audit@localhost" \
  GIT_COMMITTER_NAME="copilot-audit" \
  GIT_COMMITTER_EMAIL="copilot-audit@localhost" \
  git -C "$AUDIT_REPO" commit -m "$message" --quiet
}

# ---------------------------------------------------------------------------
# Append a JSON line to the session transcript JSONL file
# ---------------------------------------------------------------------------
append_transcript() {
  local json_line="$1"
  local sdir
  sdir="$(session_dir)"
  echo "$json_line" >> "$sdir/session-transcript.jsonl"
}

# ---------------------------------------------------------------------------
# Full initialisation for sessionStart: read stdin, load config, generate
# session ID, set up branch. Call this ONLY from session-start.sh.
# ---------------------------------------------------------------------------
init_audit_session_start() {
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for audit hooks. Install it: https://jqlang.github.io/jq/" >&2
    exit 2
  fi

  read_input
  load_config
  generate_session_id

  if [[ "$AUDIT_MODE" == "per-session" ]]; then
    ensure_branch "session/$SESSION_ID"
  else
    ensure_branch "$AUDIT_BRANCH"
  fi
}

# ---------------------------------------------------------------------------
# Full initialisation for all hooks except sessionStart: read stdin, load
# config, read session ID from temp file, set up branch.
# ---------------------------------------------------------------------------
init_audit() {
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for audit hooks. Install it: https://jqlang.github.io/jq/" >&2
    exit 2
  fi

  read_input
  load_config
  read_session_id

  if [[ "$AUDIT_MODE" == "per-session" ]]; then
    ensure_branch "session/$SESSION_ID"
  else
    ensure_branch "$AUDIT_BRANCH"
  fi
}
