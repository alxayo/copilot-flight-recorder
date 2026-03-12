# postToolUse hook — capture workspace diff and tool results after file-editing tools
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\audit-common.ps1"

Initialize-Audit

$toolName = Get-JsonField "toolName"
$toolArgsRaw = Get-JsonField "toolArgs"
$toolResult = try { $script:HookInput.toolResult } catch { $null }
$resultType = if ($toolResult) { $toolResult.resultType } else { "" }
$resultText = if ($toolResult) { $toolResult.textResultForLlm } else { "" }

# File-editing tools that should trigger diff capture
$fileEditTools = @("edit", "create", "bash")

if ($toolName -notin $fileEditTools) {
    # Non-editing tools: still log tool result to transcript
    $transcriptEntry = [PSCustomObject]@{
        type             = "toolResult"
        toolName         = $toolName
        resultType       = $resultType
        textResultForLlm = $resultText
        timestamp        = $script:Timestamp
    } | ConvertTo-Json -Compress
    Add-TranscriptEntry $transcriptEntry
    exit 0
}

# Parse toolArgs to extract file path
$affectedFile = $null
if ($toolArgsRaw) {
    try {
        $parsedArgs = $toolArgsRaw | ConvertFrom-Json
        $affectedFile = if ($parsedArgs.path) { $parsedArgs.path } elseif ($parsedArgs.filePath) { $parsedArgs.filePath } else { $null }
    } catch {
        $affectedFile = $null
    }
}

# Capture workspace diff (tracked files: staged + unstaged vs HEAD)
$diff = ""
if ($script:HookCwd -and (Test-Path (Join-Path $script:HookCwd ".git"))) {
    $diffLines = git -C $script:HookCwd diff HEAD 2>$null
    if (-not $diffLines) {
        $diffLines = git -C $script:HookCwd diff 2>$null
    }
    if ($diffLines -is [array]) { $diff = $diffLines -join "`n" }
    elseif ($diffLines) { $diff = $diffLines }
}

# For new/untracked files (e.g. create), capture content directly
if (-not $diff -and $affectedFile -and (Test-Path $affectedFile)) {
    $content = Get-Content $affectedFile -Raw
    $diff = "new file: $affectedFile`n---`n$content"
}

$sdir = Get-SessionDir
New-Item -ItemType Directory -Path $sdir -Force | Out-Null

# For bash tool, skip patch if diff is empty (read-only command)
if ($toolName -eq "bash" -and -not $diff) {
    $counter        = Get-NextCounter
    $resultFileName = "${counter}-tool-result.json"
    $resultDestPath = Join-Path $sdir $resultFileName

    $resultObj = [PSCustomObject]@{
        sessionId       = $script:SessionId
        toolName        = $toolName
        resultType      = $resultType
        textResultForLlm = $resultText
        timestamp       = $script:Timestamp
    }
    $resultObj | ConvertTo-Json -Depth 4 | Set-Content -Path $resultDestPath -Encoding UTF8

    $transcriptEntry = [PSCustomObject]@{
        type             = "toolResult"
        toolName         = $toolName
        resultType       = $resultType
        textResultForLlm = $resultText
        timestamp        = $script:Timestamp
    } | ConvertTo-Json -Compress
    Add-TranscriptEntry $transcriptEntry

    New-AuditCommit -FilePath "sessions/$($script:SessionId)/$resultFileName" `
      -Message "[$($script:SessionId)] tool result: $toolName (no changes)"
    exit 0
}

# Nothing changed and not bash — skip but log transcript
if (-not $diff) {
    $transcriptEntry = [PSCustomObject]@{
        type             = "toolResult"
        toolName         = $toolName
        resultType       = $resultType
        textResultForLlm = $resultText
        timestamp        = $script:Timestamp
    } | ConvertTo-Json -Compress
    Add-TranscriptEntry $transcriptEntry
    exit 0
}

$counter        = Get-NextCounter
$patchFileName  = "${counter}-changes.patch"
$metaFileName   = "${counter}-changes.meta.json"
$resultFileName = "${counter}-tool-result.json"
$patchDestPath  = Join-Path $sdir $patchFileName
$metaDestPath   = Join-Path $sdir $metaFileName
$resultDestPath = Join-Path $sdir $resultFileName

Set-Content -Path $patchDestPath -Value $diff -Encoding UTF8

# Build metadata sidecar for cross-referencing audit repo ↔ source repo
$workspaceHead   = ""
$fileContentHash = $null
if ($script:HookCwd -and (Test-Path (Join-Path $script:HookCwd ".git"))) {
    $workspaceHead = git -C $script:HookCwd rev-parse HEAD 2>$null
    if (-not $workspaceHead) { $workspaceHead = "" }
}
if ($affectedFile -and (Test-Path $affectedFile)) {
    $fileContentHash = git hash-object $affectedFile 2>$null
    if (-not $fileContentHash) { $fileContentHash = $null }
}

$meta = [PSCustomObject]@{
    sessionId       = $script:SessionId
    filePath        = if ($affectedFile) { $affectedFile } else { "unknown" }
    workspaceHead   = $workspaceHead
    fileContentHash = $fileContentHash
    timestamp       = $script:Timestamp
    toolName        = $toolName
    patchFile       = $patchFileName
}
$meta | ConvertTo-Json -Depth 4 | Set-Content -Path $metaDestPath -Encoding UTF8

# Write tool result
$resultObj = [PSCustomObject]@{
    sessionId        = $script:SessionId
    toolName         = $toolName
    resultType       = $resultType
    textResultForLlm = $resultText
    timestamp        = $script:Timestamp
}
$resultObj | ConvertTo-Json -Depth 4 | Set-Content -Path $resultDestPath -Encoding UTF8

# Append tool result to transcript
$transcriptEntry = [PSCustomObject]@{
    type             = "toolResult"
    toolName         = $toolName
    resultType       = $resultType
    textResultForLlm = $resultText
    timestamp        = $script:Timestamp
} | ConvertTo-Json -Compress
Add-TranscriptEntry $transcriptEntry

$shortFile = if ($affectedFile) { Split-Path $affectedFile -Leaf } else { "unknown" }

git -C $script:AuditRepo add -- "sessions/$($script:SessionId)/$metaFileName"
git -C $script:AuditRepo add -- "sessions/$($script:SessionId)/$resultFileName"
New-AuditCommit -FilePath "sessions/$($script:SessionId)/$patchFileName" `
  -Message "[$($script:SessionId)] changes: $toolName on $shortFile"
