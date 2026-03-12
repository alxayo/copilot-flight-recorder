# install-plugin.ps1 — Install copilot-flight-recorder plugin locally for Copilot CLI
#
# Usage:
#   .\scripts\install-plugin.ps1 [-Target <DIR>]
#
# If -Target is omitted the plugin is installed to $HOME\.copilot-plugins\copilot-flight-recorder
param(
    [string]$Target
)
$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot   = Split-Path -Parent $ScriptDir
$PluginName = "copilot-flight-recorder"

if (-not $Target) {
    $Target = Join-Path $HOME ".copilot-plugins\$PluginName"
}

Write-Host "==> Installing $PluginName to $Target"

# Create target directories
New-Item -ItemType Directory -Path (Join-Path $Target ".github\plugin")        -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Target ".github\hooks\scripts") -Force | Out-Null

# Copy plugin manifest
Copy-Item (Join-Path $RepoRoot ".github\plugin\plugin.json") (Join-Path $Target ".github\plugin\plugin.json") -Force
Copy-Item (Join-Path $RepoRoot ".github\plugin\README.md")   (Join-Path $Target ".github\plugin\README.md")   -Force

# Copy hooks config and scripts
Copy-Item (Join-Path $RepoRoot ".github\hooks\copilot-cli-audit.json")  (Join-Path $Target ".github\hooks\copilot-cli-audit.json") -Force
Copy-Item (Join-Path $RepoRoot ".github\hooks\scripts\*.sh")        (Join-Path $Target ".github\hooks\scripts\")           -Force
Copy-Item (Join-Path $RepoRoot ".github\hooks\scripts\*.ps1")       (Join-Path $Target ".github\hooks\scripts\")           -Force

# Copy supporting files
Copy-Item (Join-Path $RepoRoot ".env.example") (Join-Path $Target ".env.example") -Force
Copy-Item (Join-Path $RepoRoot "README.md")    (Join-Path $Target "README.md")    -Force

Write-Host ""
Write-Host "Plugin installed to: $Target"
Write-Host ""
Write-Host "The plugin hooks will be automatically discovered by Copilot CLI"
Write-Host "when running from a workspace that contains the .github/hooks directory."
Write-Host ""
Write-Host "Don't forget to configure your audit repo:"
Write-Host "  `$env:COPILOT_AUDIT_REPO = 'C:\path\to\your\audit-repo'"
Write-Host "  (or create a .env file in your workspace root)"
