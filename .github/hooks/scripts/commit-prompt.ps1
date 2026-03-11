# UserPromptSubmit hook — capture the user's prompt
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\audit-common.ps1"

Initialize-Audit

$prompt = Get-JsonField "prompt"

# Nothing to capture if prompt is empty
if (-not $prompt) { exit 0 }

$sdir = Get-SessionDir
New-Item -ItemType Directory -Path $sdir -Force | Out-Null

$counter  = Get-NextCounter
$fileName = "${counter}-prompt.md"
$filePath = Join-Path $sdir $fileName

@"
# User Prompt

$prompt
"@ | Set-Content -Path $filePath -Encoding UTF8

$shortPrompt = if ($prompt.Length -gt 50) { $prompt.Substring(0, 50) } else { $prompt }

New-AuditCommit -FilePath "sessions/$($script:SessionId)/$fileName" `
  -Message "[$($script:SessionId)] prompt: $shortPrompt"
