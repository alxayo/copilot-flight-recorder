# errorOccurred hook — log errors during agent execution
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\audit-common.ps1"

Initialize-Audit

$errorObj = try { $script:HookInput.error } catch { $null }
$errorName    = if ($errorObj -and $errorObj.name)    { $errorObj.name }    else { "" }
$errorMessage = if ($errorObj -and $errorObj.message) { $errorObj.message } else { "" }
$errorStack   = if ($errorObj -and $errorObj.stack)   { $errorObj.stack }   else { "" }

$sdir = Get-SessionDir
New-Item -ItemType Directory -Path $sdir -Force | Out-Null

$counter  = Get-NextCounter
$fileName = "${counter}-error.json"
$filePath = Join-Path $sdir $fileName

$errorEntry = [PSCustomObject]@{
    sessionId = $script:SessionId
    error     = [PSCustomObject]@{
        name    = $errorName
        message = $errorMessage
        stack   = $errorStack
    }
    timestamp = $script:Timestamp
}
$errorEntry | ConvertTo-Json -Depth 4 | Set-Content -Path $filePath -Encoding UTF8

# Append to transcript
$transcriptEntry = [PSCustomObject]@{
    type      = "error"
    error     = [PSCustomObject]@{
        name    = $errorName
        message = $errorMessage
        stack   = $errorStack
    }
    timestamp = $script:Timestamp
} | ConvertTo-Json -Compress -Depth 4
Add-TranscriptEntry $transcriptEntry

$shortError = if ($errorMessage.Length -gt 50) { $errorMessage.Substring(0, 50) } else { $errorMessage }

New-AuditCommit -FilePath "sessions/$($script:SessionId)/$fileName" `
  -Message "[$($script:SessionId)] error: $shortError"
