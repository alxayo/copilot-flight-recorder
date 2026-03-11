# Plan: Copilot Chat Audit Hooks

## TL;DR
Build a set of VS Code Copilot agent hooks that capture every prompt, response, and file change from chat sessions and commit them linearly to a configurable external git repo. Supports two branching modes: **flat** (all commits on a single branch) and **per-session** (one branch per chat session).

## Architecture

### Hook Events Used
| Hook Event | Purpose |
|---|---|
| `SessionStart` | Initialize audit session: resolve config, create branch (per-session mode), commit session-start metadata |
| `UserPromptSubmit` | Capture user prompt text, commit to audit repo |
| `PostToolUse` | When file-editing tools fire, capture git diff from workspace, commit patch to audit repo |
| `Stop` | Copy full transcript (via `transcript_path`), commit to audit repo, finalize session |

### Branching Modes
- **Flat**: All commits go to a single configurable branch (default: `main`). Commit messages include session ID for filtering.
- **Per-session**: Each chat session gets a branch named `session/<sessionId>` (or `session/<timestamp>` if ID unavailable). Branch is created at `SessionStart` and finalized at `Stop`.

### Config Resolution (priority order)
1. Environment variables: `COPILOT_AUDIT_REPO` (path to git repo), `COPILOT_AUDIT_MODE` (`flat` | `per-session`)
2. `.env` file in workspace root with same variable names
3. Defaults: mode=`flat`, branch=`main`

### Audit Repo Commit Structure
```
<audit-repo>/
├── sessions/
│   └── <sessionId>/
│       ├── 001-prompt.md          # User prompt text
│       ├── 002-changes.patch      # File diff after tool use
│       ├── 003-prompt.md          # Next prompt
│       ├── 004-changes.patch      # Next changes
│       ├── ...
│       └── transcript.json        # Full transcript at session end
```
Each file is its own commit with a descriptive message like:
- `[<sessionId>] prompt: <first 50 chars of prompt>`
- `[<sessionId>] changes: <tool_name> on <file_path>`
- `[<sessionId>] transcript: session complete`

A monotonic counter per session ensures linear ordering.

## Files to Create

### Hook Configuration
- `.github/hooks/copilot-audit.json` — Hook config wiring all 4 events to scripts

### Scripts (cross-platform)
- `.github/hooks/scripts/audit-common.sh` — Shared Bash utilities (config loading, git helpers)
- `.github/hooks/scripts/audit-common.ps1` — Shared PowerShell utilities
- `.github/hooks/scripts/session-start.sh` + `.ps1` — SessionStart hook
- `.github/hooks/scripts/commit-prompt.sh` + `.ps1` — UserPromptSubmit hook
- `.github/hooks/scripts/commit-changes.sh` + `.ps1` — PostToolUse hook (filters for file-editing tools only)
- `.github/hooks/scripts/finalize-session.sh` + `.ps1` — Stop hook

## Steps

### Phase 1: Foundation
1. Create `.github/hooks/` directory structure
2. Create `audit-common.sh` and `audit-common.ps1` with:
   - Config resolution (env var → .env file → defaults)
   - `audit_commit()` helper: stages file in audit repo, commits with message, increments counter
   - `ensure_branch()` helper: creates/switches branch based on mode
   - Session state file management (counter stored in `<audit-repo>/sessions/<sessionId>/.state`)
3. Create `.env.example` documenting required variables

### Phase 2: Hook Scripts (*parallel with each other, depends on Phase 1*)
4. **session-start scripts**: Read stdin JSON, extract `sessionId`. Initialize session dir in audit repo. In per-session mode, create and checkout branch. Commit a `000-session-start.md` with metadata (timestamp, workspace path, source). *Parallel with steps 5-7*
5. **commit-prompt scripts**: Read stdin JSON, extract `prompt` and `sessionId`. Write prompt to `NNN-prompt.md`. Commit to audit repo. *Parallel with steps 4, 6, 7*
6. **commit-changes scripts**: Read stdin JSON, extract `tool_name`, `tool_input`. Filter: only act on file-editing tools (`editFiles`, `create_file`, `replace_string_in_file`, `insert_text_in_file`, `delete_file`). Run `git diff` in workspace to capture changes. Write to `NNN-changes.patch`. Commit to audit repo. *Parallel with steps 4, 5, 7*
7. **finalize-session scripts**: Read stdin JSON, extract `transcript_path` and `sessionId`. Copy transcript to session dir as `transcript.json`. Commit to audit repo. In per-session mode, optionally push branch. *Parallel with steps 4, 5, 6*

### Phase 3: Hook Config (*depends on Phase 2*)
8. Create `.github/hooks/copilot-audit.json` wiring all events to scripts with OS-specific commands (bash for linux/osx, powershell for windows)
9. Set appropriate `timeout` values (15s for prompt/changes, 30s for session-start/finalize)

### Phase 4: Documentation
10. Create `README.md` or section in existing docs explaining setup: clone audit repo, set env vars, open workspace

## Verification
1. **Config loading**: Set `COPILOT_AUDIT_REPO` to a test git repo. Open VS Code, start a chat session. Check the "GitHub Copilot Chat Hooks" output channel for hook execution logs.
2. **SessionStart**: Verify `000-session-start.md` is committed in audit repo with correct metadata.
3. **Prompt capture**: Send a prompt in chat. Verify `001-prompt.md` appears as a commit in audit repo.
4. **File change capture**: Ask Copilot to edit a file. Verify `002-changes.patch` is committed with the diff.
5. **Transcript**: End the session. Verify `transcript.json` is committed.
6. **Flat mode**: Verify all commits land on `main` with session ID in commit messages.
7. **Per-session mode**: Set `COPILOT_AUDIT_MODE=per-session`. Start new session. Verify a new branch `session/<id>` is created and all commits land there.
8. **Cross-platform**: Test on both Windows (PowerShell) and macOS/Linux (Bash).

## Decisions
- **Diffs only** (no full file snapshots) — keeps audit repo lightweight
- **Full transcript committed at session end** via `transcript_path` provided by hooks API
- **No auto-push** by default — user controls when to push audit repo (can add as opt-in config)
- **PostToolUse filtering** — only capture diffs for file-editing tool names, ignore other tools (terminal, search, etc.)
- **Counter-based ordering** — monotonic integer prefix ensures commit order matches interaction order
- **Scope**: This is a workspace-level hook setup. Does NOT include a VS Code extension or global installation mechanism.

## Further Considerations
1. **Auto-push**: Should the `Stop` hook also `git push` the audit repo? Recommend making this opt-in via `COPILOT_AUDIT_PUSH=true` env var.
2. **Git diff timing for PostToolUse**: The workspace `git diff` captures all uncommitted changes, not just the tool's change. Consider tracking last-known state to produce incremental diffs, or accept that diffs may include manual edits too. Recommend: use `git diff` at each PostToolUse and `git stash`-like tracking in the state file to isolate per-tool diffs.
3. **Concurrency**: If multiple VS Code windows use the same audit repo simultaneously, commits could interleave. Recommend file-locking or separate branches per workspace.
