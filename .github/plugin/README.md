---
name: "Copilot Flight Recorder (CLI Edition)"
description: "A full audit trail for GitHub Copilot CLI agent sessions. Captures every prompt, tool invocation, file change, error, and session lifecycle event, committing them linearly to a configurable external git repo."
tags: ["audit", "logging", "compliance", "hooks", "session-recording", "copilot-cli"]
---

# Copilot Flight Recorder — CLI Edition

A Copilot CLI hooks plugin that captures a complete audit trail of every agent session — prompts, tool invocations, file changes, errors, and reconstructed transcripts — committed linearly to a separate git repo.

## What This Plugin Provides

Six lifecycle hooks that fire automatically during Copilot CLI agent sessions:

| Hook Event | What It Does |
|---|---|
| **sessionStart** | Creates session directory, generates session ID, captures initial prompt |
| **userPromptSubmitted** | Captures each user prompt and commits it |
| **preToolUse** | Logs tool invocation intent before execution (with optional deny) |
| **postToolUse** | After file-editing tools run, captures `git diff`, tool result, and commits |
| **errorOccurred** | Logs error name, message, and stack trace |
| **sessionEnd** | Writes session summary, commits reconstructed transcript, cleanup |

## Requirements

- **GitHub Copilot CLI** with hooks support
- **Git** 2.20+ on PATH
- **jq** (Linux/macOS only)
- **PowerShell** 5.1+ (Windows) or **Bash** 4+ (Linux/macOS)

## Setup

1. Install this plugin (see installation methods below)
2. Create a separate git repo for audit logs:
   ```bash
   mkdir ~/copilot-audit && cd ~/copilot-audit
   git init && git commit --allow-empty -m "init audit repo"
   ```
3. Set the `COPILOT_AUDIT_REPO` environment variable to the audit repo path, or create a `.env` file in your workspace root:
   ```
   COPILOT_AUDIT_REPO=/path/to/your/audit-repo
   ```

## Configuration

| Variable | Description | Default |
|---|---|---|
| `COPILOT_AUDIT_REPO` | **Required.** Path to the audit git repo | — |
| `COPILOT_AUDIT_MODE` | `flat` or `per-session` | `flat` |
| `COPILOT_AUDIT_BRANCH` | Branch name for flat mode | `main` |
| `COPILOT_AUDIT_PUSH` | Auto-push after session ends | `false` |

## Branching Modes

- **Flat**: All commits on one branch. Session ID in commit messages for filtering.
- **Per-session**: Each chat session gets its own `session/<sessionId>` branch.
