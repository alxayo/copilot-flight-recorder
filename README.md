# copilot-flight-recorder

A full audit trail for your GitHub Copilot agent sessions. Every prompt, response, and file change is captured and committed linearly to a configurable external git repo — giving you a complete record you can review, search, or use to reproduce sessions exactly as they happened.

## System Requirements

- **VS Code** 1.99 or later with the **GitHub Copilot Chat** extension
- **Git** 2.20+ available on `PATH`
- **jq** (Linux/macOS only) — [install guide](https://jqlang.github.io/jq/download/)
- **PowerShell** 5.1+ (Windows) or **Bash** 4+ (Linux/macOS)
- **Operating systems**: Windows, macOS, Linux

## Coding Agent Compatibility

This hook system uses the [VS Code Copilot Chat Hooks API](https://code.visualstudio.com/docs/copilot/customization/hooks), which relies on `.github/hooks/copilot-audit.json` and the specific hook events (`SessionStart`, `UserPromptSubmit`, `PostToolUse`, `Stop`) provided by the VS Code Copilot extension.

### ✅ Supported

| Agent | Notes |
|---|---|
| **GitHub Copilot Chat (VS Code)** | Fully supported. All four hook events are used for complete audit coverage: session lifecycle, prompt capture, file-change diffs, and transcript export. |

### ❌ Not Supported

| Agent | Why |
|---|---|
| **GitHub Copilot CLI** (`gh copilot`) | The CLI has no hook or plugin system. It does not load `.github/hooks/` configs or emit any of the required events. A shell wrapper around `gh copilot` would be needed for CLI audit logging. |
| **Anthropic Claude Code** | Claude Code has its own hooks system (configured via `.claude/settings.json`) with different event names, JSON payload shapes, and tool names. It lacks `SessionStart` and `UserPromptSubmit` events, so prompt capture and session initialization would not be possible. The core git/audit scripts could be adapted, but the hook wiring, JSON parsing, and tool filtering would need to be rewritten. |
| **Cursor** | Cursor does not expose a hooks API compatible with this system. |
| **Other editors/agents** | Any tool that does not implement the VS Code Copilot Chat Hooks specification will not work with this system. |

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

## Same-Repo Audit with Git Worktrees

By default the audit trail lives in a **separate** git repository. If you prefer to keep everything in a single repo — your source code on `main` and audit data on an `audit` branch — you can use a [git worktree](https://git-scm.com/docs/git-worktree).

### Why a worktree?

The hooks need to `git checkout` the audit branch and commit files to it. If the audit repo is your main workspace directory, that checkout would **switch your working tree away from your development branch**, breaking your editor state and any in-progress work. A worktree gives you a second checkout directory backed by the exact same `.git` database, so both branches can be checked out simultaneously without interference.

### One-time setup

Run these commands from your project root (e.g. `C:\code\myproject`):

```powershell
# 1. Create an orphan "audit" branch with no files (keeps history separate from code)
git checkout --orphan audit
git rm -rf .
git commit --allow-empty -m "audit: init"
git checkout main          # switch back to your working branch

# 2. Create a worktree directory so the audit branch has its own checkout
#    Place it next to (not inside) your project directory
git worktree add ../myproject-audit audit
```

On Linux/macOS the commands are identical — just adjust the path style:
```bash
git worktree add ../myproject-audit audit
```

This creates `../myproject-audit/` checked out on the `audit` branch.

### Configure the `.env`

Point `COPILOT_AUDIT_REPO` at the worktree directory:

```ini
# .env (in your project root)
COPILOT_AUDIT_REPO=C:\code\myproject-audit   # absolute path to the worktree
COPILOT_AUDIT_BRANCH=audit
COPILOT_AUDIT_MODE=flat
COPILOT_AUDIT_PUSH=false
```

On Linux/macOS:
```ini
COPILOT_AUDIT_REPO=/home/you/code/myproject-audit
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
│   └── <sessionId>/
│       ├── 001-session-start.md
│       ├── 002-prompt.md
│       ├── 003-changes.patch
│       └── transcript.json
```

- Both directories share the **same `.git` database**, same remotes, same refs.
- Commits made in either directory are immediately visible to the other.
- Branches are independent — updating `audit` never touches `main` and vice versa.

### Pushing the audit branch

You can push the `audit` branch from **either** directory at any time, regardless of which branch is checked out in the other:

```powershell
# From your main workspace
git push origin audit

# Or from the worktree
git -C C:\code\myproject-audit push origin audit
```

To push automatically after each session, set `COPILOT_AUDIT_PUSH=true` in your `.env`.

### Viewing audit history from your main workspace

Since it's the same repo, all standard git commands work:

```powershell
# See audit commits
git log audit --oneline

# Show a specific session's files
git show audit:sessions/<sessionId>/001-session-start.md

# Diff between two audit commits
git diff audit~5..audit
```

### Removing the worktree (keeping the branch)

If you no longer need the separate checkout directory:

```powershell
git worktree remove ../myproject-audit
```

The `audit` branch and all its commits remain in the repo. You can recreate the worktree at any time with `git worktree add`.

### Important notes

- **Don't nest the worktree inside your project** — place it alongside (e.g. `../myproject-audit`) so that your workspace's `.gitignore` and file watchers don't interfere with it.
- The `audit` branch is an **orphan branch** with its own independent history. It shares no commits with `main` and merging it is neither required nor recommended.
- If you use **per-session mode** (`COPILOT_AUDIT_MODE=per-session`), each session creates a `session/<id>` branch. These also branch off within the same repo and are visible everywhere.
- **Concurrent sessions**: If multiple VS Code windows use the same worktree, commits may interleave. Use per-session mode or separate worktrees per workspace to avoid this.

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

## Plugin Installation

copilot-flight-recorder is packaged as a [VS Code Agent Plugin](https://code.visualstudio.com/docs/copilot/customization/agent-plugins) and can be installed in several ways.

> **Prerequisite**: Enable agent plugins in VS Code with `"chat.plugins.enabled": true`.

### Option 1: Install from a release archive

1. Download the latest `.zip` or `.tar.gz` from [Releases](https://github.com/alxayo/copilot-flight-recorder/releases).
2. Extract to a directory (e.g. `~/.copilot-plugins/copilot-flight-recorder`).
3. Add to your VS Code `settings.json`:
   ```json
   "chat.plugins.paths": {
     "/path/to/copilot-flight-recorder": true
   }
   ```

### Option 2: Install from git (clone)

```bash
git clone https://github.com/alxayo/copilot-flight-recorder.git ~/.copilot-plugins/copilot-flight-recorder
```

Then add the path to `chat.plugins.paths` as shown above.

### Option 3: Use as a marketplace source

Add the repo directly as a plugin marketplace in your VS Code `settings.json`:

```json
"chat.plugins.marketplaces": ["alxayo/copilot-flight-recorder"]
```

VS Code will discover and offer the plugin for installation automatically.

### Option 4: Use the install script

From a cloned copy of this repo:

```bash
# Linux / macOS
./scripts/install-plugin.sh

# Windows (PowerShell)
.\scripts\install-plugin.ps1
```

The script copies the plugin to `~/.copilot-plugins/copilot-flight-recorder` and prints the `settings.json` snippet to activate it.

## Building the Plugin Package

To create distributable archives from source:

```bash
# Linux / macOS
bash scripts/build-plugin.sh

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File scripts\build-plugin.ps1
```

This produces `dist/copilot-flight-recorder-<version>.zip` and `.tar.gz` archives ready for distribution.

### CI/CD

A GitHub Actions workflow (`.github/workflows/release-plugin.yml`) automatically:
1. **Validates** the plugin structure (all required files, valid JSON)
2. **Builds** the zip and tar.gz archives
3. **Publishes** them as GitHub Release assets when you push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```
