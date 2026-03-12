# copilot-flight-recorder — CLI Edition

A full audit trail for your GitHub Copilot CLI agent sessions. Every prompt, tool invocation, file change, error, and session lifecycle event is captured and committed linearly to a configurable external git repo — giving you a complete record you can review, search, or use to reproduce sessions exactly as they happened.

## System Requirements

- **GitHub Copilot CLI** with hooks support
- **Git** 2.20+ available on `PATH`
- **jq** (Linux/macOS only) — [install guide](https://jqlang.github.io/jq/download/)
- **PowerShell** 5.1+ (Windows) or **Bash** 4+ (Linux/macOS)
- **Operating systems**: Windows, macOS, Linux

## How It Works

Six [Copilot CLI hooks](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks) fire during an agent session:

| Hook Event | What It Does |
|---|---|
| **sessionStart** | Creates session directory, generates synthesized session ID, captures initial prompt |
| **userPromptSubmitted** | Writes user prompt to `NNN-prompt.md`, appends to transcript |
| **preToolUse** | Logs tool invocation intent to `NNN-tool-attempt.json` before execution |
| **postToolUse** | After file-editing tools run, captures `git diff HEAD`, writes `NNN-changes.patch` + `NNN-tool-result.json` |
| **errorOccurred** | Logs error name, message, and stack trace to `NNN-error.json` |
| **sessionEnd** | Writes session summary, commits reconstructed transcript, cleanup |

Each file gets its own commit with a descriptive message like `[cli-20260312-143022-a1b2c3d4] prompt: Fix the login bug…`.

### Session ID Synthesis

The Copilot CLI does not provide a session ID. Instead, one is synthesized at session start as `cli-YYYYMMDD-HHMMSS-<cwd-hash>` and persisted in a temp file for subsequent hooks to read.

### Transcript Reconstruction

The CLI does not provide a `transcript_path`. Instead, a `session-transcript.jsonl` file is built incrementally by each hook, appending one JSON line per event. The final transcript is committed at session end.

### Branching Modes

- **Flat** (default): All commits go to a single branch (default `main`). Session ID in commit messages for filtering.
- **Per-session**: Each session gets its own `session/<sessionId>` branch.

### Audit Repo Structure

```
<audit-repo>/
└── sessions/
    └── cli-20260312-143022-a1b2c3d4/
        ├── 001-session-start.md
        ├── 002-prompt.md
        ├── 003-tool-attempt.json
        ├── 004-changes.patch
        ├── 004-changes.meta.json
        ├── 005-tool-result.json
        ├── 006-prompt.md
        ├── 007-tool-attempt.json
        ├── 008-changes.patch
        ├── 008-changes.meta.json
        ├── 009-tool-result.json
        ├── 010-error.json
        ├── 011-session-end.md
        └── session-transcript.jsonl
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

4. **Run Copilot CLI** from the workspace directory. The hooks in `.github/hooks/copilot-cli-audit.json` are loaded automatically.

## Same-Repo Audit with Git Worktrees

By default the audit trail lives in a **separate** git repository. If you prefer to keep everything in a single repo — your source code on `main` and audit data on an `audit` branch — you can use a [git worktree](https://git-scm.com/docs/git-worktree).

### Why a worktree?

The hooks need to `git checkout` the audit branch and commit files to it. If the audit repo is your main workspace directory, that checkout would **switch your working tree away from your development branch**, breaking your editor state and any in-progress work. A worktree gives you a second checkout directory backed by the exact same `.git` database, so both branches can be checked out simultaneously without interference.

### One-time setup

Run these commands from your project root:

```bash
# 1. Create an orphan "audit" branch with no files (keeps history separate from code)
git checkout --orphan audit
git rm -rf .
git commit --allow-empty -m "audit: init"
git checkout main

# 2. Create a worktree directory alongside your project
git worktree add ../myproject-audit audit
```

### Configure the `.env`

Point `COPILOT_AUDIT_REPO` at the worktree directory:

```ini
# .env (in your project root)
COPILOT_AUDIT_REPO=/path/to/myproject-audit
COPILOT_AUDIT_BRANCH=audit
COPILOT_AUDIT_MODE=flat
COPILOT_AUDIT_PUSH=false
```

### How it works under the hood

```
myproject/                  ← your normal workspace (branch: main)
├── .git/                   ← shared git database
├── .env                    ← points COPILOT_AUDIT_REPO to the worktree
├── .github/hooks/          ← copilot-flight-recorder hooks
└── src/                    ← your source code

myproject-audit/            ← worktree checkout (branch: audit)
├── sessions/
│   └── cli-20260312-143022-a1b2c3d4/
│       ├── 001-session-start.md
│       ├── 002-prompt.md
│       ├── 003-tool-attempt.json
│       ├── 004-changes.patch
│       └── session-transcript.jsonl
```

- Both directories share the **same `.git` database**, same remotes, same refs.
- Commits made in either directory are immediately visible to the other.
- Branches are independent — updating `audit` never touches `main` and vice versa.

### Pushing the audit branch

```bash
# From your main workspace
git push origin audit

# Or from the worktree
git -C /path/to/myproject-audit push origin audit
```

To push automatically after each session, set `COPILOT_AUDIT_PUSH=true`.

### Viewing audit history from your main workspace

```bash
# See audit commits
git log audit --oneline

# Show a specific session's files
git show audit:sessions/<sessionId>/001-session-start.md

# Diff between two audit commits
git diff audit~5..audit
```

### Removing the worktree

```bash
git worktree remove ../myproject-audit
```

The `audit` branch and all its commits remain in the repo.

### Important notes

- **Don't nest the worktree inside your project** — place it alongside so file watchers don't interfere.
- The `audit` branch is an **orphan branch** with independent history.
- **Concurrent sessions**: Use per-session mode or separate worktrees to avoid commit interleaving.

## Configuration

All settings can be provided as environment variables or in a `.env` file at the workspace root. Environment variables take priority.

| Variable | Description | Default |
|---|---|---|
| `COPILOT_AUDIT_REPO` | **Required.** Absolute path to the audit git repo | — |
| `COPILOT_AUDIT_MODE` | `flat` or `per-session` | `flat` |
| `COPILOT_AUDIT_BRANCH` | Branch name for flat mode | `main` |
| `COPILOT_AUDIT_PUSH` | Auto-push after session ends (`true`/`false`) | `false` |

## Tools Tracked

The `postToolUse` hook captures diffs and tool results for these CLI tools:

- `edit` — file editing
- `create` — file creation
- `bash` — shell command execution (patch skipped if diff is empty)

All other tools are logged in the transcript but don't generate `.patch` files.

## Cross-Referencing Audit Data with Source Commits

Each `postToolUse` event produces a `.meta.json` sidecar alongside the `.patch` file:

```json
{
  "sessionId": "cli-20260312-143022-a1b2c3d4",
  "filePath": "src/handler.ts",
  "workspaceHead": "abc123def456",
  "fileContentHash": "789abc012def",
  "timestamp": 1741862100000,
  "toolName": "edit",
  "patchFile": "004-changes.patch"
}
```

### Useful queries

```bash
# All files changed by a specific session
jq -s '[.[] | select(.sessionId == "cli-20260312-143022-a1b2c3d4") | .filePath]' \
  sessions/*/???-changes.meta.json

# All sessions that touched a specific file
jq -s '[.[] | select(.filePath | endswith("handler.ts")) | .sessionId] | unique' \
  sessions/*/???-changes.meta.json

# Full cross-reference table
jq -s '[.[] | {sessionId, filePath, workspaceHead, toolName}]' \
  sessions/*/???-changes.meta.json
```

## Verification

1. Set `COPILOT_AUDIT_REPO` to a test git repo.
2. Run `copilot -p "Show git status"` from the workspace.
3. Check for `001-session-start.md` in the audit repo.
4. Send a prompt → check for `NNN-prompt.md`.
5. Ask the agent to edit a file → check for `NNN-changes.patch` + `NNN-tool-result.json`.
6. Check for `NNN-tool-attempt.json` (pre-tool logging).
7. End the session → check for `NNN-session-end.md` and `session-transcript.jsonl`.
8. For per-session mode, set `COPILOT_AUDIT_MODE=per-session` and verify a `session/<id>` branch is created.

## Security Notes

- The `.env` file is git-ignored to prevent leaking local paths.
- Hook scripts run with the same permissions as the Copilot CLI. Review them before use.
- No secrets are stored in scripts — all config flows through environment variables.
- The `preToolUse` hook can be extended with deny logic for policy enforcement.

## Limitations

- `git diff HEAD` captures **cumulative** workspace changes, not per-tool incremental diffs.
- Brand-new untracked files (from `create`) are captured as raw content rather than unified diff format.
- No file-locking: concurrent sessions targeting the same audit repo could interleave commits. Use per-session mode to avoid this.
- LLM reasoning text between tool calls is **not captured** — the CLI provides no hook for model-generated text.
- The reconstructed transcript is missing LLM reasoning — it only contains events the hooks observe.

## Plugin Installation

### Option 1: Install from a release archive

1. Download the latest `.zip` or `.tar.gz` from [Releases](https://github.com/alxayo/copilot-flight-recorder/releases).
2. Extract to your workspace's `.github` directory.

### Option 2: Install from git (clone)

```bash
git clone -b copilot-cli https://github.com/alxayo/copilot-flight-recorder.git ~/.copilot-plugins/copilot-flight-recorder
```

### Option 3: Use the install script

From a cloned copy of this repo:

```bash
# Linux / macOS
./scripts/install-plugin.sh

# Windows (PowerShell)
.\scripts\install-plugin.ps1
```

## Building the Plugin Package

To create distributable archives from source:

```bash
# Linux / macOS
bash scripts/build-plugin.sh

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File scripts\build-plugin.ps1
```

This produces `dist/copilot-flight-recorder-<version>.zip` and `.tar.gz` archives.

### CI/CD

A GitHub Actions workflow (`.github/workflows/release-plugin.yml`) automatically:
1. **Validates** the plugin structure (all required files, valid JSON)
2. **Builds** the zip and tar.gz archives
3. **Publishes** them as GitHub Release assets when you push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```
