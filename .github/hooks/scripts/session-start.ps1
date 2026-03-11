# SessionStart hook — initialise the audit session
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\audit-common.ps1"

Initialize-Audit

$sdir = Get-SessionDir
New-Item -ItemType Directory -Path $sdir -Force | Out-Null

# Initialise the monotonic counter for this session
Set-Content -Path (Join-Path $sdir ".counter") -Value "0" -NoNewline

$source = Get-JsonField "source"
if (-not $source) { $source = "new" }

$counter  = Get-NextCounter
$fileName = "${counter}-session-start.md"
$filePath = Join-Path $sdir $fileName

@"
# Session Start

- **Session ID**: $($script:SessionId)
- **Timestamp**: $($script:Timestamp)
- **Workspace**: $($script:HookCwd)
- **Source**: $source
- **Mode**: $($script:AuditMode)
"@ | Set-Content -Path $filePath -Encoding UTF8

New-AuditCommit -FilePath "sessions/$($script:SessionId)/$fileName" `
  -Message "[$($script:SessionId)] session start"
