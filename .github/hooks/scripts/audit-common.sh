#!/usr/bin/env bash
# Shared utilities for Copilot Audit Hooks (Bash/Linux/macOS)
set -euo pipefail

AUDIT_REPO=""
AUDIT_MODE="flat"
AUDIT_BRANCH="main"
AUDIT_PUSH="false"

INPUT=""
SESSION_ID=""
HOOK_CWD=""
TIMESTAMP=""
TRANSCRIPT_PATH=""

# ---------------------------------------------------------------------------
# Read JSON from stdin and extract common fields
# ---------------------------------------------------------------------------
read_input() {
  INPUT=$(cat)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
  HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  TIMESTAMP=$(echo "$INPUT" | jq -r '.timestamp // empty')
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

  if [[ -z "$SESSION_ID" ]]; then
    echo "ERROR: No session_id in hook input" >&2
    exit 2
  fi
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
# Full initialisation: read stdin, load config, set up branch
# Call this at the top of every hook script.
# ---------------------------------------------------------------------------
init_audit() {
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required for audit hooks. Install it: https://jqlang.github.io/jq/" >&2
    exit 2
  fi

  read_input
  load_config

  if [[ "$AUDIT_MODE" == "per-session" ]]; then
    ensure_branch "session/$SESSION_ID"
  else
    ensure_branch "$AUDIT_BRANCH"
  fi
}
