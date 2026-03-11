---
name: "Copilot Flight Recorder"
description: "A full audit trail for GitHub Copilot agent sessions. Captures every prompt, response, and file change, committing them linearly to a configurable external git repo."
tags: ["audit", "logging", "compliance", "hooks", "session-recording"]
---

# Copilot Flight Recorder

A VS Code Copilot agent plugin that captures a complete audit trail of every chat session — prompts, file changes, and transcripts — committed linearly to a separate git repo.

## What This Plugin Provides

Four lifecycle hooks that fire automatically during Copilot Chat sessions:

| Hook Event | What It Does |
|---|---|
| **SessionStart** | Creates a session directory in the audit repo, commits metadata |
| **UserPromptSubmit** | Captures each user prompt and commits it |
| **PostToolUse** | After file-editing tools run, captures `git diff` and commits the patch |
| **Stop** | Copies the full session transcript and commits it |

## Requirements

- **VS Code** 1.99+ with GitHub Copilot Chat extension
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
