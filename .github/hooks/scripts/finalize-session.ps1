# Stop hook — copy transcript and finalise the audit session
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\audit-common.ps1"

Initialize-Audit

$sdir = Get-SessionDir
New-Item -ItemType Directory -Path $sdir -Force | Out-Null

# Copy full transcript if the path was provided and the file exists
if ($script:TranscriptPath -and (Test-Path $script:TranscriptPath)) {
    $dest = Join-Path $sdir "transcript.json"
    Copy-Item -Path $script:TranscriptPath -Destination $dest -Force

    New-AuditCommit -FilePath "sessions/$($script:SessionId)/transcript.json" `
      -Message "[$($script:SessionId)] transcript: session complete"
}

# Auto-push if configured
if ($script:AuditPush -eq "true") {
    $branch = if ($script:AuditMode -eq "per-session") {
        "session/$($script:SessionId)"
    } else {
        $script:AuditBranch
    }
    git -C $script:AuditRepo push origin $branch --quiet 2>$null
}
