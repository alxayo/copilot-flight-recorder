# build-plugin.ps1 — Package copilot-flight-recorder as a distributable Copilot CLI agent plugin
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = Split-Path -Parent $ScriptDir

# Read version from plugin.json
$PluginJsonPath = Join-Path $RepoRoot ".github\plugin\plugin.json"
$PluginJson     = Get-Content $PluginJsonPath -Raw | ConvertFrom-Json
$PluginName     = $PluginJson.name
$PluginVersion  = $PluginJson.version
$BuildDir       = Join-Path $RepoRoot "dist"
$StageDir       = Join-Path $BuildDir $PluginName

Write-Host "==> Building $PluginName v$PluginVersion"

# Clean previous build
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $StageDir ".github\plugin")       -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $StageDir ".github\hooks\scripts") -Force | Out-Null

# ---- Copy plugin manifest and README ----
Copy-Item (Join-Path $RepoRoot ".github\plugin\plugin.json") (Join-Path $StageDir ".github\plugin\plugin.json")
Copy-Item (Join-Path $RepoRoot ".github\plugin\README.md")   (Join-Path $StageDir ".github\plugin\README.md")

# ---- Copy hook configuration ----
Copy-Item (Join-Path $RepoRoot ".github\hooks\copilot-cli-audit.json") (Join-Path $StageDir ".github\hooks\copilot-cli-audit.json")

# ---- Copy all hook scripts ----
Copy-Item (Join-Path $RepoRoot ".github\hooks\scripts\*.sh")  (Join-Path $StageDir ".github\hooks\scripts\") -Force
Copy-Item (Join-Path $RepoRoot ".github\hooks\scripts\*.ps1") (Join-Path $StageDir ".github\hooks\scripts\") -Force

# ---- Copy config example and docs ----
Copy-Item (Join-Path $RepoRoot ".env.example") (Join-Path $StageDir ".env.example")
Copy-Item (Join-Path $RepoRoot "README.md")    (Join-Path $StageDir "README.md")

# ---- Create the zip archive ----
Write-Host "==> Creating archive in $BuildDir\"
$ZipPath = Join-Path $BuildDir "$PluginName-$PluginVersion.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path $StageDir -DestinationPath $ZipPath

# ---- Summary ----
Write-Host ""
Write-Host "Plugin package built successfully:"
Write-Host "  $ZipPath"
Write-Host ""
Write-Host "Install locally by extracting to your workspace .github directory."
