# Shared utilities for Copilot CLI Audit Hooks (PowerShell / Windows)
$ErrorActionPreference = "Stop"

$script:AuditRepo   = ""
$script:AuditMode   = "flat"
$script:AuditBranch = "main"
$script:AuditPush   = "false"

$script:HookInput      = $null
$script:SessionId      = ""
$script:HookCwd        = ""
$script:Timestamp      = ""

# ---------------------------------------------------------------------------
# Read JSON from stdin and extract common fields
# CLI payloads have: timestamp (Unix ms), cwd. No session_id or transcript_path.
# ---------------------------------------------------------------------------
function Read-HookInput {
    $raw = [Console]::In.ReadToEnd()
    $script:HookInput      = $raw | ConvertFrom-Json
    $script:HookCwd        = $script:HookInput.cwd
    $script:Timestamp      = $script:HookInput.timestamp
}

# Extract a single property from the stored HookInput object
function Get-JsonField {
    param([string]$FieldName)
    try {
        $script:HookInput | Select-Object -ExpandProperty $FieldName -ErrorAction SilentlyContinue
    } catch {
        $null
    }
}

# ---------------------------------------------------------------------------
# Load configuration: environment variables -> .env file -> defaults
# ---------------------------------------------------------------------------
function Read-Config {
    $cwd = if ($script:HookCwd) { $script:HookCwd } else { "." }
    $envFile = Join-Path $cwd ".env"
    if (Test-Path $envFile) {
        foreach ($line in Get-Content $envFile) {
            $trimmed = $line.Trim()
            if ($trimmed.StartsWith("#") -or $trimmed -eq "") { continue }
            if ($trimmed -match "^([^=]+)=(.*)$") {
                $key   = $Matches[1].Trim()
                $value = $Matches[2].Trim().Trim('"', "'")
                switch ($key) {
                    "COPILOT_AUDIT_REPO"   { if (-not $env:COPILOT_AUDIT_REPO)   { $env:COPILOT_AUDIT_REPO   = $value } }
                    "COPILOT_AUDIT_MODE"   { if (-not $env:COPILOT_AUDIT_MODE)   { $env:COPILOT_AUDIT_MODE   = $value } }
                    "COPILOT_AUDIT_BRANCH" { if (-not $env:COPILOT_AUDIT_BRANCH) { $env:COPILOT_AUDIT_BRANCH = $value } }
                    "COPILOT_AUDIT_PUSH"   { if (-not $env:COPILOT_AUDIT_PUSH)   { $env:COPILOT_AUDIT_PUSH   = $value } }
                }
            }
        }
    }

    $script:AuditRepo   = if ($env:COPILOT_AUDIT_REPO)   { $env:COPILOT_AUDIT_REPO }   else { "" }
    $script:AuditMode   = if ($env:COPILOT_AUDIT_MODE)   { $env:COPILOT_AUDIT_MODE }   else { "flat" }
    $script:AuditBranch = if ($env:COPILOT_AUDIT_BRANCH) { $env:COPILOT_AUDIT_BRANCH } else { "main" }
    $script:AuditPush   = if ($env:COPILOT_AUDIT_PUSH)   { $env:COPILOT_AUDIT_PUSH }   else { "false" }

    if (-not $script:AuditRepo) {
        Write-Error "COPILOT_AUDIT_REPO is not set. Set it as an environment variable or in .env"
        exit 2
    }
    if (-not (Test-Path (Join-Path $script:AuditRepo ".git"))) {
        Write-Error "$($script:AuditRepo) is not a git repository"
        exit 2
    }
}

# ---------------------------------------------------------------------------
# Session ID synthesis
# CLI provides no session_id. We synthesize one at sessionStart and persist
# it in a temp file keyed by cwd hash + parent PID.
# ---------------------------------------------------------------------------
function Get-CwdHash {
    $cwd = if ($script:HookCwd) { $script:HookCwd } else { "unknown" }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cwd)
    $hash = $md5.ComputeHash($bytes)
    ($hash | ForEach-Object { $_.ToString("x2") }) -join "" | ForEach-Object { $_.Substring(0, 8) }
}

function Get-SessionIdFile {
    $hash = Get-CwdHash
    Join-Path $env:TEMP "copilot-audit-${hash}-$PID"
}

function New-SessionId {
    $datestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $hash = Get-CwdHash
    $script:SessionId = "cli-${datestamp}-${hash}"
    $idFile = Get-SessionIdFile
    Set-Content -Path $idFile -Value $script:SessionId -NoNewline
}

function Read-SessionId {
    $idFile = Get-SessionIdFile
    if (Test-Path $idFile) {
        $script:SessionId = (Get-Content $idFile -Raw).Trim()
    } else {
        Write-Error "No session ID file found at $idFile. Was sessionStart called?"
        exit 2
    }
}

function Remove-SessionIdFile {
    $idFile = Get-SessionIdFile
    if (Test-Path $idFile) { Remove-Item $idFile -Force }
}

# ---------------------------------------------------------------------------
# Session directory path inside the audit repo
# ---------------------------------------------------------------------------
function Get-SessionDir {
    Join-Path (Join-Path $script:AuditRepo "sessions") $script:SessionId
}

# ---------------------------------------------------------------------------
# Get and increment the monotonic counter for this session (zero-padded 3 digits)
# ---------------------------------------------------------------------------
function Get-NextCounter {
    $sdir = Get-SessionDir
    $counterFile = Join-Path $sdir ".counter"
    $counter = 0

    if (Test-Path $counterFile) {
        $counter = [int](Get-Content $counterFile -Raw).Trim()
    }
    $counter++
    Set-Content -Path $counterFile -Value $counter -NoNewline
    "{0:D3}" -f $counter
}

# ---------------------------------------------------------------------------
# Ensure the target branch is checked out in the audit repo
# ---------------------------------------------------------------------------
function Set-AuditBranch {
    param([string]$Branch)

    $current = git -C $script:AuditRepo branch --show-current 2>$null
    if ($current -eq $Branch) { return }

    $null = git -C $script:AuditRepo show-ref --verify --quiet "refs/heads/$Branch" 2>$null
    if ($LASTEXITCODE -eq 0) {
        git -C $script:AuditRepo checkout $Branch --quiet 2>$null
    } else {
        git -C $script:AuditRepo checkout -b $Branch --quiet 2>$null
    }
}

# ---------------------------------------------------------------------------
# Stage a file and commit it to the audit repo
# ---------------------------------------------------------------------------
function New-AuditCommit {
    param(
        [string]$FilePath,   # relative to audit repo root
        [string]$Message
    )

    git -C $script:AuditRepo add -- $FilePath
    $env:GIT_AUTHOR_NAME     = "copilot-audit"
    $env:GIT_AUTHOR_EMAIL    = "copilot-audit@localhost"
    $env:GIT_COMMITTER_NAME  = "copilot-audit"
    $env:GIT_COMMITTER_EMAIL = "copilot-audit@localhost"
    git -C $script:AuditRepo commit -m $Message --quiet 2>$null
}

# ---------------------------------------------------------------------------
# Append a JSON line to the session transcript JSONL file
# ---------------------------------------------------------------------------
function Add-TranscriptEntry {
    param([string]$JsonLine)
    $sdir = Get-SessionDir
    $transcriptPath = Join-Path $sdir "session-transcript.jsonl"
    Add-Content -Path $transcriptPath -Value $JsonLine -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Full initialisation for sessionStart: read stdin, load config, generate
# session ID, set up branch. Call this ONLY from session-start.ps1.
# ---------------------------------------------------------------------------
function Initialize-AuditSessionStart {
    Read-HookInput
    Read-Config
    New-SessionId

    if ($script:AuditMode -eq "per-session") {
        Set-AuditBranch "session/$($script:SessionId)"
    } else {
        Set-AuditBranch $script:AuditBranch
    }
}

# ---------------------------------------------------------------------------
# Full initialisation for all hooks except sessionStart: read stdin, load
# config, read session ID from temp file, set up branch.
# ---------------------------------------------------------------------------
function Initialize-Audit {
    Read-HookInput
    Read-Config
    Read-SessionId

    if ($script:AuditMode -eq "per-session") {
        Set-AuditBranch "session/$($script:SessionId)"
    } else {
        Set-AuditBranch $script:AuditBranch
    }
}
