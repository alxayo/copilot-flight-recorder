# PostToolUse hook — capture workspace diff after file-editing tools
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\audit-common.ps1"

Initialize-Audit

$toolName = Get-JsonField "tool_name"

# Only act on file-editing tools; silently skip everything else.
$fileEditTools = @(
    "create_file"
    "replace_string_in_file"
    "multi_replace_string_in_file"
    "edit_notebook_file"
    "insert_text_in_file"
    "delete_file"
)

if ($toolName -notin $fileEditTools) { exit 0 }

# Determine the affected file path from tool_input
$affectedFile = if ($toolName -eq "multi_replace_string_in_file") {
    try { $script:HookInput.tool_input.replacements[0].filePath } catch { $null }
} else {
    try { $script:HookInput.tool_input.filePath } catch { $null }
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

# For new/untracked files (e.g. create_file), capture content directly
if (-not $diff -and $affectedFile -and (Test-Path $affectedFile)) {
    $content = Get-Content $affectedFile -Raw
    $diff = "new file: $affectedFile`n---`n$content"
}

# Nothing changed — skip
if (-not $diff) { exit 0 }

$sdir = Get-SessionDir
New-Item -ItemType Directory -Path $sdir -Force | Out-Null

$counter  = Get-NextCounter
$fileName = "${counter}-changes.patch"
$destPath = Join-Path $sdir $fileName

Set-Content -Path $destPath -Value $diff -Encoding UTF8

$shortFile = if ($affectedFile) { Split-Path $affectedFile -Leaf } else { "unknown" }

New-AuditCommit -FilePath "sessions/$($script:SessionId)/$fileName" `
  -Message "[$($script:SessionId)] changes: $toolName on $shortFile"
