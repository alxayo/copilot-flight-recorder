# sessionStart hook — initialise the CLI audit session
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\audit-common.ps1"

Initialize-AuditSessionStart

$sdir = Get-SessionDir
New-Item -ItemType Directory -Path $sdir -Force | Out-Null

# Initialise the monotonic counter for this session
Set-Content -Path (Join-Path $sdir ".counter") -Value "0" -NoNewline

$source = Get-JsonField "source"
if (-not $source) { $source = "new" }

$initialPrompt = Get-JsonField "initialPrompt"

$counter  = Get-NextCounter
$fileName = "${counter}-session-start.md"
$filePath = Join-Path $sdir $fileName

$content = @"
# Session Start

- **Session ID**: $($script:SessionId)
- **Timestamp**: $($script:Timestamp)
- **Workspace**: $($script:HookCwd)
- **Source**: $source
- **Mode**: $($script:AuditMode)
"@

if ($initialPrompt) {
    $content += "`n`n## Initial Prompt`n`n$initialPrompt"
}

$content | Set-Content -Path $filePath -Encoding UTF8

# Initialize transcript with session start entry
$transcriptEntry = [PSCustomObject]@{
    type          = "sessionStart"
    source        = $source
    initialPrompt = if ($initialPrompt) { $initialPrompt } else { "" }
    timestamp     = $script:Timestamp
} | ConvertTo-Json -Compress
Add-TranscriptEntry $transcriptEntry

New-AuditCommit -FilePath "sessions/$($script:SessionId)/$fileName" `
  -Message "[$($script:SessionId)] session start"
