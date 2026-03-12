# sessionEnd hook — finalize session: summary, transcript commit, cleanup
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\audit-common.ps1"

Initialize-Audit

$reason = Get-JsonField "reason"
if (-not $reason) { $reason = "unknown" }

$sdir = Get-SessionDir
New-Item -ItemType Directory -Path $sdir -Force | Out-Null

# Append sessionEnd to transcript
$transcriptEntry = [PSCustomObject]@{
    type      = "sessionEnd"
    reason    = $reason
    timestamp = $script:Timestamp
} | ConvertTo-Json -Compress
Add-TranscriptEntry $transcriptEntry

# Write session-end summary
$counter  = Get-NextCounter
$fileName = "${counter}-session-end.md"
$transcriptFile = Join-Path $sdir "session-transcript.jsonl"

$toolCount   = 0
$errorCount  = 0
$promptCount = 0
if (Test-Path $transcriptFile) {
    $lines = Get-Content $transcriptFile
    $toolCount   = ($lines | Select-String '"type":"toolResult"').Count
    $errorCount  = ($lines | Select-String '"type":"error"').Count
    $promptCount = ($lines | Select-String '"type":"userPrompt"').Count
}

$summary = @"
# Session End: $($script:SessionId)

- **Reason**: $reason
- **Timestamp**: $($script:Timestamp)
- **Prompts**: $promptCount
- **Tool uses**: $toolCount
- **Errors**: $errorCount
"@
Set-Content -Path (Join-Path $sdir $fileName) -Value $summary -Encoding UTF8

# Commit transcript and summary together
git -C $script:AuditRepo add -- "sessions/$($script:SessionId)/session-transcript.jsonl" 2>$null
git -C $script:AuditRepo add -- "sessions/$($script:SessionId)/$fileName" 2>$null
New-AuditCommit -FilePath "sessions/$($script:SessionId)/$fileName" `
  -Message "[$($script:SessionId)] session end: $reason"

# Cleanup temp session ID file
Remove-SessionIdFile

# Auto-push if configured
if ($script:AuditPush -eq "true") {
    $branch = if ($script:AuditMode -eq "per-session") {
        "session/$($script:SessionId)"
    } else {
        $script:AuditBranch
    }
    git -C $script:AuditRepo push origin $branch --quiet 2>$null
}
