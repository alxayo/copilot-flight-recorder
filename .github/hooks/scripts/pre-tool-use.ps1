# preToolUse hook — log tool invocation intent before execution
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\audit-common.ps1"

Initialize-Audit

$toolName = Get-JsonField "toolName"
$toolArgsRaw = Get-JsonField "toolArgs"

# Parse toolArgs JSON string gracefully; fall back to raw string on failure
$toolArgsParsed = $toolArgsRaw
if ($toolArgsRaw) {
    try {
        $toolArgsParsed = $toolArgsRaw | ConvertFrom-Json
    } catch {
        $toolArgsParsed = $toolArgsRaw
    }
}

$sdir = Get-SessionDir
New-Item -ItemType Directory -Path $sdir -Force | Out-Null

$counter  = Get-NextCounter
$fileName = "${counter}-tool-attempt.json"
$filePath = Join-Path $sdir $fileName

$attempt = [PSCustomObject]@{
    sessionId = $script:SessionId
    toolName  = $toolName
    toolArgs  = $toolArgsParsed
    timestamp = $script:Timestamp
}
$attempt | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8

# Append to transcript
$transcriptEntry = [PSCustomObject]@{
    type      = "toolAttempt"
    toolName  = $toolName
    toolArgs  = if ($toolArgsRaw) { $toolArgsRaw } else { "" }
    timestamp = $script:Timestamp
} | ConvertTo-Json -Compress
Add-TranscriptEntry $transcriptEntry

New-AuditCommit -FilePath "sessions/$($script:SessionId)/$fileName" `
  -Message "[$($script:SessionId)] tool attempt: $toolName"

# Exit 0 to allow tool execution (no deny by default)
exit 0
