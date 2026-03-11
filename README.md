# Copilot Chat Audit Hooks

Capture every prompt, response, and file change from VS Code Copilot chat sessions and commit them linearly to a configurable external git repo.

## How It Works

Four [VS Code agent hooks](https://code.visualstudio.com/docs/copilot/customization/hooks) fire during a Copilot chat session:

| Hook Event | What It Does |
|---|---|
| **SessionStart** | Creates the session directory in the audit repo, commits a `000-session-start.md` with metadata |
| **UserPromptSubmit** | Writes the user's prompt to `NNN-prompt.md`, commits it |
| **PostToolUse** | After a file-editing tool runs, captures `git diff HEAD` from the workspace and commits a `NNN-changes.patch` |
| **Stop** | Copies the full transcript (via `transcript_path`) to `transcript.json`, commits it |

Each file gets its own commit with a descriptive message like `[<sessionId>] prompt: Fix the login bug…`.

### Branching Modes

- **Flat** (default): All commits go to a single branch (default `main`). Commit messages include the session ID for filtering.
- **Per-session**: Each chat session gets its own branch named `session/<sessionId>`.

### Audit Repo Structure

```
<audit-repo>/
└── sessions/
    └── <sessionId>/
        ├── 001-session-start.md
        ├── 002-prompt.md
        ├── 003-changes.patch
        ├── 004-prompt.md
        ├── 005-changes.patch
        └── transcript.json
```

## Prerequisites

- **Git** available on `PATH`
- **jq** (Linux/macOS only) — [install guide](https://jqlang.github.io/jq/download/)
- An **initialised git repository** to use as the audit repo:
  ```bash
  mkdir ~/copilot-audit && cd ~/copilot-audit && git init
  ```

## Setup

1. **Clone or copy** this workspace (the one containing `.github/hooks/`) into your project, or copy the `.github/hooks/` directory into an existing project's root.

2. **Create the audit repo** (a separate git repo that will hold the audit trail):
   ```bash
   mkdir ~/copilot-audit
   cd ~/copilot-audit
   git init
   git commit --allow-empty -m "init audit repo"
   ```

3. **Configure** by copying `.env.example` to `.env` and setting at least `COPILOT_AUDIT_REPO`:
   ```bash
   cp .env.example .env
   # Edit .env:
   COPILOT_AUDIT_REPO=/home/you/copilot-audit
   ```
   Alternatively, set environment variables directly (they take priority over `.env`).

4. **Open the workspace** in VS Code. The hooks in `.github/hooks/copilot-audit.json` are loaded automatically.

5. **Start a Copilot chat session.** Check the **GitHub Copilot Chat Hooks** output channel to verify hooks are executing.

## Configuration

All settings can be provided as environment variables or in a `.env` file at the workspace root. Environment variables take priority.

| Variable | Description | Default |
|---|---|---|
| `COPILOT_AUDIT_REPO` | **Required.** Absolute path to the audit git repo | — |
| `COPILOT_AUDIT_MODE` | `flat` or `per-session` | `flat` |
| `COPILOT_AUDIT_BRANCH` | Branch name for flat mode | `main` |
| `COPILOT_AUDIT_PUSH` | Auto-push after session ends (`true`/`false`) | `false` |

## File-Editing Tools Tracked

The `PostToolUse` hook only captures diffs when these VS Code tools are used:

- `create_file`
- `replace_string_in_file`
- `multi_replace_string_in_file`
- `edit_notebook_file`
- `insert_text_in_file`
- `delete_file`

All other tools (terminal, search, etc.) are silently skipped.

## Verification

1. Set `COPILOT_AUDIT_REPO` to a test git repo and open the workspace in VS Code.
2. Start a chat session → check for `001-session-start.md` in the audit repo.
3. Send a prompt → check for `002-prompt.md`.
4. Ask Copilot to edit a file → check for `003-changes.patch`.
5. End the session → check for `transcript.json`.
6. For per-session mode, set `COPILOT_AUDIT_MODE=per-session` and verify a `session/<id>` branch is created.

## Security Notes

- The `.env` file is git-ignored to prevent leaking local paths.
- Hook scripts run with the same permissions as VS Code. Review them before use in shared repos.
- Consider using `chat.tools.edits.autoApprove` to prevent the agent from modifying hook scripts during a session.
- No secrets are stored in scripts — all config flows through environment variables.

## Limitations

- `git diff HEAD` captures **cumulative** workspace changes, not per-tool incremental diffs. If you make manual edits between tool uses, those appear in the patch too.
- Brand-new untracked files (from `create_file`) are captured as raw content rather than unified diff format.
- No file-locking: concurrent sessions targeting the same audit repo could interleave commits. Use per-session mode or separate audit repos to avoid this.
