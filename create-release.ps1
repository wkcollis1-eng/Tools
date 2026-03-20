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

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequireGh

. "$PSScriptRoot\repos.ps1"

if ($Repo -notin $Repos) {
    Write-Host "Unknown repo '$Repo'. Valid options:" -ForegroundColor Red
    $Repos | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# ── Validation gate — HVAC baseline repo requires validate-all.ps1 ────────────
# Use release.ps1 instead of create-release.ps1 for the HVAC repo — it runs
# the full validation gate before tagging. This script will proceed if you
# confirm, but bypasses the HALT check.
if ($Repo -eq "Residential-HVAC-Performance-Baseline-") {
    Write-Host ""
    Write-Host "WARNING: $Repo has a validation gate." -ForegroundColor Yellow
    Write-Host "Use .\release.ps1 to enforce HALT-level validation before tagging." -ForegroundColor Yellow
    $confirm = Read-Host "Proceed with create-release.ps1 anyway? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Cancelled. Run: .\release.ps1 -Repo $Repo -Tag $Tag -Title `"$Title`" -Month YYYY-MM" -ForegroundColor Cyan
        exit 0
    }
    Write-Host "Proceeding without validation — ensure data is clean." -ForegroundColor Yellow
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
