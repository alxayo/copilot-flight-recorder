# Plan: Copilot CLI Audit Hooks (Flight Recorder — CLI Edition)

> **Branch**: `copilot-cli` (never merged into `main`)
> **Relationship to VS Code system**: Independent implementation with the same audit-to-git recording approach, adapted entirely for the Copilot CLI hooks API.

---

## 1. Overview

Build a Copilot CLI hook system that captures every prompt, tool invocation, tool result, error, and sub-agent delegation from CLI agent sessions, committing them linearly to a configurable external git repo — the same flight-recorder pattern as the VS Code system on `main`.

The CLI system uses six hook events (vs four on VS Code) and reconstructs a session transcript from accumulated events (since CLI does not provide a `transcript_path`).

---

## 2. Hook Events

| CLI Event | Purpose | VS Code Equivalent |
|---|---|---|
| `sessionStart` | Initialize audit session, create session directory, commit metadata | `SessionStart` |
| `userPromptSubmitted` | Capture user prompt text, commit to audit repo | `UserPromptSubmit` |
| `preToolUse` | Log tool invocation intent before execution, monitor sub-agents, optional policy enforcement | *(none in current VS Code system)* |
| `postToolUse` | Capture workspace diff after file-editing tools, log tool results | `PostToolUse` |
| `errorOccurred` | Log errors during agent execution | *(none in VS Code)* |
| `sessionEnd` | Finalize session, commit reconstructed transcript, log end reason | `Stop` |

---

## 3. CLI Input Schemas

### 3a. Common Fields (present in every event)

```json
{
  "timestamp": 1704614400000,
  "cwd": "/path/to/project"
}
```

| Field | Type | Notes |
|---|---|---|
| `timestamp` | number | Unix milliseconds (not ISO 8601 like VS Code) |
| `cwd` | string | Current working directory |

**Fields NOT provided by CLI** (present in VS Code):

| Missing Field | Impact | Mitigation |
|---|---|---|
| `sessionId` | No native session ID in any payload | Synthesize at `sessionStart`, persist in temp file, read in subsequent hooks |
| `transcript_path` | No transcript file to copy | Reconstruct from accumulated events (JSONL) |
| `hookEventName` | Not provided | Known from which script is running — no impact |

### 3b. sessionStart

```json
{
  "timestamp": 1704614400000,
  "cwd": "/path/to/project",
  "source": "new",
  "initialPrompt": "Create a new feature"
}
```

| Field | Notes |
|---|---|
| `source` | `"new"`, `"resume"`, or `"startup"` (richer than VS Code's always-`"new"`) |
| `initialPrompt` | User's initial prompt if provided (bonus — not available in VS Code) |

**Output**: Ignored by CLI.

### 3c. userPromptSubmitted

```json
{
  "timestamp": 1704614500000,
  "cwd": "/path/to/project",
  "prompt": "Fix the authentication bug"
}
```

**Output**: Ignored by CLI.

### 3d. preToolUse

```json
{
  "timestamp": 1704614600000,
  "cwd": "/path/to/project",
  "toolName": "bash",
  "toolArgs": "{\"command\":\"rm -rf dist\",\"description\":\"Clean build directory\"}"
}
```

| Field | Type | Notes |
|---|---|---|
| `toolName` | string | Tool name: `"bash"`, `"edit"`, `"create"`, `"view"`, `"runSubagent"`, etc. |
| `toolArgs` | string | **JSON string** that must be parsed to extract arguments |

**Output** (optional — only for deny):
```json
{
  "permissionDecision": "deny",
  "permissionDecisionReason": "Reason for blocking"
}
```

Only `"deny"` is currently processed by CLI. Exit 0 with no output (or `"allow"`) to permit execution.

### 3e. postToolUse

```json
{
  "timestamp": 1704614700000,
  "cwd": "/path/to/project",
  "toolName": "bash",
  "toolArgs": "{\"command\":\"npm test\"}",
  "toolResult": {
    "resultType": "success",
    "textResultForLlm": "All tests passed (15/15)"
  }
}
```

| Field | Notes |
|---|---|
| `toolName` | Same as preToolUse |
| `toolArgs` | Same JSON string format |
| `toolResult.resultType` | `"success"`, `"failure"`, or `"denied"` |
| `toolResult.textResultForLlm` | The result text the LLM sees |

**Output**: Ignored by CLI. (Unlike VS Code, cannot inject `additionalContext`.)

**Key difference from VS Code**: VS Code provides `tool_name` (snake_case), `tool_input` (parsed object), `tool_response` (string). CLI provides `toolName` (camelCase), `toolArgs` (JSON **string**), `toolResult` (object).

### 3f. sessionEnd

```json
{
  "timestamp": 1704618000000,
  "cwd": "/path/to/project",
  "reason": "complete"
}
```

| Field | Notes |
|---|---|
| `reason` | `"complete"`, `"error"`, `"abort"`, `"timeout"`, or `"user_exit"` |

**Output**: Ignored by CLI.

### 3g. errorOccurred

```json
{
  "timestamp": 1704614800000,
  "cwd": "/path/to/project",
  "error": {
    "message": "Network timeout",
    "name": "TimeoutError",
    "stack": "TimeoutError: Network timeout\n    at ..."
  }
}
```

**Output**: Ignored by CLI.

---

## 4. CLI Tool Names

The CLI uses different tool names than VS Code for file operations:

| CLI Tool | Purpose | VS Code Equivalent |
|---|---|---|
| `edit` | Edit an existing file | `replace_string_in_file`, `multi_replace_string_in_file` |
| `create` | Create a new file | `create_file` |
| `bash` | Run shell command (may modify files) | *(run_in_terminal — not tracked in VS Code)* |
| `view` | Read a file (no modification) | *(read_file — not tracked)* |
| `runSubagent` | Delegate to a sub-agent | *(SubagentStart — separate event in VS Code)* |

### File-Editing Tool Filter for postToolUse

For capturing diffs, track these tools:

| Tool | Capture Diff? | Rationale |
|---|---|---|
| `edit` | **Yes** | Always modifies a file |
| `create` | **Yes** | Always creates a file |
| `bash` | **Yes, if diff is non-empty** | May or may not modify files — capture patch only when changes exist (but ALWAYS log to transcript/tool-result) |
| `view` | **No** | Read-only |
| `runSubagent` | **No** (sub-agent's own tools will trigger their own hooks) | Delegation only |
| Other tools | **No** | Read-only or non-file operations |

---

## 5. Sub-Agent Monitoring

Copilot CLI delegates to sub-agents via the `runSubagent` tool. Since `preToolUse` fires before **all** tools, we capture sub-agent delegations automatically:

- `toolName` will be `"runSubagent"`
- `toolArgs` will contain the instructions/prompt being passed to the sub-agent

The `pre-tool-use` script logs this as a `NNN-tool-attempt.json` entry like any other tool. No special handling needed beyond recognizing `runSubagent` in the log.

---

## 6. Transcript Reconstruction

CLI does not provide `transcript_path`. Instead, we reconstruct a transcript by appending to a `session-transcript.jsonl` file throughout the session:

| Event | Data Appended |
|---|---|
| `sessionStart` | `{type: "sessionStart", source, initialPrompt, timestamp}` |
| `userPromptSubmitted` | `{type: "prompt", prompt, timestamp}` |
| `preToolUse` | `{type: "toolAttempt", toolName, toolArgs, timestamp}` |
| `postToolUse` | `{type: "toolResult", toolName, resultType, textResultForLlm, timestamp}` |
| `errorOccurred` | `{type: "error", error, timestamp}` |
| `sessionEnd` | `{type: "sessionEnd", reason, timestamp}` |

At `sessionEnd`, the completed `session-transcript.jsonl` is committed to the audit repo.

**What this captures**: User inputs, tool invocations with arguments, tool results with LLM-visible output, errors, session lifecycle.

**What this misses**: The LLM's own reasoning and natural-language replies between tool calls. No CLI hook captures model-generated text. Prompts + tool calls + tool results covers the actionable content.

---

## 7. Session ID Synthesis

Since CLI provides no `sessionId`, we synthesize one at `sessionStart` and persist it for the duration of the session:

**Strategy**:
1. At `sessionStart`: Generate `cli-<YYYYMMDD-HHMMSS>-<cwd-hash-8chars>`, write to temp file `/tmp/copilot-audit-<cwd-hash>-<ppid>` (incorporating Parent Process ID to prevent concurrent terminal collisions)
2. At subsequent hooks (`userPromptSubmitted`, `preToolUse`, `postToolUse`, `errorOccurred`): Read session ID from temp file
3. At `sessionEnd`: Read session ID, then delete the temp file

**Edge cases**:
- Stale temp files (crash/kill without `sessionEnd`): `sessionStart` always overwrites, so the next session self-heals
- Concurrent sessions from same `cwd`: Mitigated by incorporating the Shell/CLI Process ID (`$PPID` in Bash, `$PID` in PowerShell) into the temp filename.

**Windows equivalent**: Use `$env:TEMP\copilot-audit-<cwd-hash>-<pid>` in PowerShell.

---

## 8. Config Resolution

Same as VS Code system — no changes needed:

1. Environment variables: `COPILOT_AUDIT_REPO`, `COPILOT_AUDIT_MODE`, `COPILOT_AUDIT_BRANCH`, `COPILOT_AUDIT_PUSH`
2. `.env` file in workspace root
3. Defaults: mode=`flat`, branch=`main`, push=`false`

---

## 9. Audit Repo Structure

```
<audit-repo>/
└── sessions/
    └── cli-20260312-143022-a1b2c3d4/
        ├── 001-session-start.md
        ├── 002-prompt.md
        ├── 003-tool-attempt.json       ← preToolUse (NEW)
        ├── 004-changes.patch           ← postToolUse (same as VS Code)
        ├── 004-changes.meta.json       ← postToolUse metadata (same)
        ├── 005-tool-result.json        ← postToolUse result data (NEW)
        ├── 006-prompt.md
        ├── 007-tool-attempt.json
        ├── 008-changes.patch
        ├── 008-changes.meta.json
        ├── 009-tool-result.json
        ├── 010-error.json              ← errorOccurred (NEW)
        ├── 011-session-end.md          ← sessionEnd reason (NEW)
        └── session-transcript.jsonl    ← reconstructed transcript (NEW)
```

Commit messages follow the same pattern: `[<sessionId>] prompt: <first 50 chars>`, `[<sessionId>] tool attempt: bash`, `[<sessionId>] changes: edit on handler.ts`, etc.

---

## 10. What Gets Recorded (Comparison)

| Data | VS Code (main) | CLI (copilot-cli) |
|---|---|---|
| Session start metadata | ✅ timestamp, cwd, source | ✅ timestamp, cwd, source, **initialPrompt** (bonus) |
| User prompts | ✅ `prompt` | ✅ `prompt` |
| Pre-tool invocation intent | ❌ not captured | ✅ `toolName` + `toolArgs` before execution |
| Sub-agent delegations | ❌ separate SubagentStart event (not used) | ✅ via `preToolUse` when `toolName == "runSubagent"` |
| File-change diffs | ✅ `git diff HEAD` | ✅ `git diff HEAD` (same approach) |
| Change metadata (sidecar) | ✅ `.meta.json` with workspace HEAD, content hash | ✅ same |
| Tool execution results | ❌ not captured | ✅ `toolResult.resultType` + `textResultForLlm` |
| Errors | ❌ not captured | ✅ error name, message, stack |
| Session end reason | ❌ not provided | ✅ complete/error/abort/timeout/user_exit |
| Full transcript | ✅ native `transcript_path` → `transcript.json` | ⚠️ reconstructed from events (missing LLM reasoning) |
| Policy enforcement (deny) | ❌ not implemented | ✅ `preToolUse` can deny dangerous commands |

---

## 11. What Cannot Be Recorded

| Data | Reason |
|---|---|
| LLM reasoning / natural-language replies | No hook captures model-generated text between tool calls |
| Notebook edits | `edit_notebook_file` is VS Code-only; CLI doesn't edit notebooks |
| Context compaction events | CLI has no `PreCompact` equivalent |
| Agent stop blocking | CLI `sessionEnd` output is ignored; cannot force agent to continue |

---

## 12. Files to Create

All files live in the same directory structure as the VS Code system. On the `copilot-cli` branch, the VS Code-specific `copilot-audit.json` is replaced.

### Hook Configuration
| File | Purpose |
|---|---|
| `.github/hooks/copilot-cli-audit.json` | CLI-format hook config wiring all 6 events to scripts |

### Scripts (cross-platform, Bash + PowerShell)
| File | Hook Event | Purpose |
|---|---|---|
| `.github/hooks/scripts/audit-common.sh` | *(shared)* | Config loading, git helpers, session ID synthesis, transcript accumulator |
| `.github/hooks/scripts/audit-common.ps1` | *(shared)* | PowerShell equivalent |
| `.github/hooks/scripts/session-start.sh` + `.ps1` | `sessionStart` | Initialize session dir, write session-start.md, create temp session ID file |
| `.github/hooks/scripts/commit-prompt.sh` + `.ps1` | `userPromptSubmitted` | Write prompt to NNN-prompt.md, append to transcript |
| `.github/hooks/scripts/pre-tool-use.sh` + `.ps1` | `preToolUse` | Write NNN-tool-attempt.json, append to transcript, optional deny |
| `.github/hooks/scripts/commit-changes.sh` + `.ps1` | `postToolUse` | Capture diff, write NNN-changes.patch + meta.json + tool-result.json, append to transcript |
| `.github/hooks/scripts/log-error.sh` + `.ps1` | `errorOccurred` | Write NNN-error.json, append to transcript |
| `.github/hooks/scripts/finalize-session.sh` + `.ps1` | `sessionEnd` | Write NNN-session-end.md, commit transcript, cleanup temp file, optional push |

### Supporting Files
| File | Purpose |
|---|---|
| `.env.example` | Config documentation (same variables as VS Code system) |
| `.gitignore` | Ignore `.env` and `dist/` |
| `README.md` | CLI-specific setup and usage docs |
| `.github/plugin/plugin.json` | Plugin manifest referencing CLI config |
| `.github/plugin/README.md` | Plugin description for CLI edition |

---

## 13. Implementation Phases

### Phase 1: Branch Setup & Foundation

1. Create `copilot-cli` branch from `main`
2. Remove `copilot-audit.json` (VS Code-specific config)
3. Rewrite `audit-common.sh` and `audit-common.ps1`:
   - Replace `session_id` extraction with synthesis logic (generate at sessionStart, read from temp file afterwards)
   - Replace `transcript_path` handling with `append_transcript()` helper that writes to `session-transcript.jsonl`
   - Keep config resolution unchanged (env var → .env → defaults)
   - Keep `audit_commit()`, `ensure_branch()`, `next_counter()`, `session_dir()` unchanged
   - Timestamp: store as-is (Unix ms number) — no normalization needed since this is CLI-only

### Phase 2: Adapt Existing Hook Scripts

4. **session-start.sh/.ps1**: Rewrite to:
   - Generate and persist synthesized session ID to temp file
   - Initialize `.counter` file
   - Record `initialPrompt` if present (CLI bonus)
   - Initialize `session-transcript.jsonl` with session start entry
   - Commit `001-session-start.md`

5. **commit-prompt.sh/.ps1**: Rewrite to:
   - Read session ID from temp file
   - Use `prompt` field (same as VS Code — minimal change)
   - Append to transcript JSONL
   - Commit `NNN-prompt.md`

6. **commit-changes.sh/.ps1**: Rewrite for CLI tool names/schema:
   - Use `toolName` (camelCase) instead of `tool_name`
   - Filter on CLI tools: `edit`, `create`, `bash` (For `bash`, skip `.patch` generation if diff is empty, but **always** log the tool-result and append to transcript)
   - Parse `toolArgs` (JSON string) robustly: Bash (`echo "$INPUT" | jq -r '.toolArgs | fromjson | .path // empty'`), PowerShell (pipe to second `ConvertFrom-Json`)
   - Capture `toolResult.resultType` and `toolResult.textResultForLlm` — write to `NNN-tool-result.json`
   - Append tool result to transcript JSONL
   - Keep `git diff HEAD` approach and `.meta.json` sidecar unchanged
   - Commit patch, metadata, and tool result

7. **finalize-session.sh/.ps1**: Rewrite for CLI sessionEnd:
   - Read session ID from temp file
   - Write `NNN-session-end.md` with `reason` field
   - Append session end to transcript JSONL
   - Commit `session-transcript.jsonl` as final record
   - Delete temp session ID file (cleanup)
   - Auto-push if configured

### Phase 3: Create New Hook Scripts

8. **pre-tool-use.sh/.ps1** (new):
   - Read session ID from temp file
   - Extract `toolName` and `toolArgs`
   - Write `NNN-tool-attempt.json` with tool name, args, timestamp
   - Append to transcript JSONL
   - Log `runSubagent` delegations (no special handling needed — it's just another tool name)     - Mechanism for **Policy Enforcement**: Echo JSON `{"permissionDecision": "deny", "permissionReason": "blocked command"}` to stdout to block the tool if the command matches a block-list or policy violation.   - Commit to audit repo
   - Exit 0 (allow all by default — deny logic can be added later per-org)

9. **log-error.sh/.ps1** (new):
   - Read session ID from temp file
   - Extract `error.message`, `error.name`, `error.stack`, and root `timestamp`
   - Write `NNN-error.json`
   - Append to transcript JSONL
   - Commit to audit repo

### Phase 4: Hook Configuration

10. Create `.github/hooks/copilot-cli-audit.json`:
    ```json
    {
      "version": 1,
      "hooks": {
        "sessionStart": [
          {
            "type": "command",
            "bash": "./scripts/session-start.sh",
            "powershell": "./scripts/session-start.ps1",
            "cwd": ".github/hooks",
            "timeoutSec": 30
          }
        ],
        "userPromptSubmitted": [
          {
            "type": "command",
            "bash": "./scripts/commit-prompt.sh",
            "powershell": "./scripts/commit-prompt.ps1",
            "cwd": ".github/hooks",
            "timeoutSec": 15
          }
        ],
        "preToolUse": [
          {
            "type": "command",
            "bash": "./scripts/pre-tool-use.sh",
            "powershell": "./scripts/pre-tool-use.ps1",
            "cwd": ".github/hooks",
            "timeoutSec": 15
          }
        ],
        "postToolUse": [
          {
            "type": "command",
            "bash": "./scripts/commit-changes.sh",
            "powershell": "./scripts/commit-changes.ps1",
            "cwd": ".github/hooks",
            "timeoutSec": 15
          }
        ],
        "sessionEnd": [
          {
            "type": "command",
            "bash": "./scripts/finalize-session.sh",
            "powershell": "./scripts/finalize-session.ps1",
            "cwd": ".github/hooks",
            "timeoutSec": 30
          }
        ],
        "errorOccurred": [
          {
            "type": "command",
            "bash": "./scripts/log-error.sh",
            "powershell": "./scripts/log-error.ps1",
            "cwd": ".github/hooks",
            "timeoutSec": 10
          }
        ]
      }
    }
    ```

### Phase 5: Documentation & Packaging

11. Rewrite `README.md` for CLI:
    - System requirements (jq, git, bash/powershell, Copilot CLI)
    - Setup instructions (create audit repo, configure .env, clone to workspace)
    - How transcript reconstruction works
    - Audit repo structure diagram
    - Configuration table
    - Tool names tracked
    - Verification steps

12. Update `.github/plugin/plugin.json` and `.github/plugin/README.md` for CLI edition

13. Update build/install scripts if needed (same structure, different config reference)

---

## 14. Verification

1. **Config loading**: Set `COPILOT_AUDIT_REPO` to a test git repo. Run `copilot -p "Show git status"` from the workspace.
2. **sessionStart**: Verify `001-session-start.md` committed with metadata including `source` and `initialPrompt`.
3. **Prompt capture**: Send a prompt. Verify `NNN-prompt.md` committed.
4. **preToolUse logging**: Verify `NNN-tool-attempt.json` appears before each tool execution with `toolName` and `toolArgs`.
5. **File change capture**: Ask agent to edit a file. Verify `NNN-changes.patch` + `NNN-changes.meta.json` committed.
6. **Tool result capture**: Verify `NNN-tool-result.json` with `resultType` and `textResultForLlm`.
7. **Error capture**: Trigger an error. Verify `NNN-error.json` committed.
8. **Session end**: End session. Verify `NNN-session-end.md` with `reason`, and `session-transcript.jsonl` committed.
9. **Transcript reconstruction**: Open `session-transcript.jsonl` and verify it contains all events in order.
10. **Sub-agent logging**: If sub-agents fire, verify `runSubagent` appears in `NNN-tool-attempt.json`.
11. **Flat mode**: Verify all commits on `main` with session ID in messages.
12. **Per-session mode**: Set `COPILOT_AUDIT_MODE=per-session`. Verify `session/<id>` branch created.
13. **Cross-platform**: Test on both Windows (PowerShell) and macOS/Linux (Bash).

---

## 15. Design Decisions

| Decision | Rationale |
|---|---|
| Separate branch, never merged | CLI and VS Code hook APIs are different enough that dual-mode complexity isn't worth it |
| Synthesized session ID via temp file | CLI provides no session ID; temp file is simple and self-healing on next sessionStart |
| Reconstructed transcript (JSONL) | CLI has no `transcript_path`; JSONL accumulation captures actionable content |
| `bash` tool tracked with empty-diff skip | Captures file modifications from shell commands without noise from read-only commands |
| `preToolUse` logs only (no deny by default) | Keeps parity with VS Code system's audit-only approach; deny can be added per-org |
| Diffs only (no full file snapshots) | Same as VS Code — keeps audit repo lightweight |
| No auto-push by default | Same as VS Code — user controls when to push |
| Counter-based ordering | Same monotonic integer prefix ensures commit order matches interaction order |
| Tool result capture (`NNN-tool-result.json`) | CLI provides richer tool result data than VS Code; worth recording separately |

---

## 16. Risks

| Risk | Mitigation |
|---|---|
| Temp file collision (concurrent sessions from same cwd) | Unlikely in CLI (single terminal); use per-session mode or add PID to temp file name |
| Stale temp files (crash without sessionEnd) | sessionStart always overwrites; next session self-heals |
| `bash` tool produces large/noisy diffs | Empty-diff skip eliminates read-only noise; large diffs are legitimate changes |
| `toolArgs` JSON parsing failures | Graceful fallback: log raw string, continue without extracted fields |
| LLM reasoning text not captured | Fundamental API limitation — no workaround; document as known limitation |
