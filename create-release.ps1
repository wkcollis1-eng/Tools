# C:\repos\tools\create-release.ps1
# Creates a tagged GitHub release using the gh CLI.
# Requires: gh installed and authenticated (gh auth login).
#
# Usage:
#   .\create-release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026 update"
#   .\create-release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026 update" -Draft

param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Title,
    [string]$Notes = "",
    [switch]$Draft
)

if (!(Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh CLI is not installed or not on PATH. See https://cli.github.com" }

. "$PSScriptRoot\repos.ps1"

if ($Repo -notin $Repos) {
    Write-Host "Unknown repo '$Repo'. Valid options:" -ForegroundColor Red
    $Repos | ForEach-Object { Write-Host "  $_" }
    exit 1
}

$ghArgs = @(
    "release", "create", $Tag,
    "--repo", "wkcollis1-eng/$Repo",
    "--title", $Title
)

if ($Notes -ne "") {
    $ghArgs += @("--notes", $Notes)
} else {
    $ghArgs += @("--notes", "$Title.")
}

if ($Draft) { $ghArgs += "--draft" }

Write-Host "Creating release $Tag in $Repo..." -ForegroundColor Green
& gh @ghArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "Release creation failed. Tag may already exist — use a new patch number." -ForegroundColor Red
    exit 1
}

Write-Host "Release $Tag created$(if ($Draft) {' (draft)' } else { '' })." -ForegroundColor Cyan
