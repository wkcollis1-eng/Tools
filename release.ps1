# C:\repos\Tools\release.ps1
# Creates a tagged GitHub release with validation gate for the HVAC baseline repo.
# For the Residential-HVAC-Performance-Baseline- repo, runs validate-all.ps1
# for the target month before tagging — a HALT stops the release.
# For all other repos, tags immediately.
#
# Usage:
#   .\release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026 — cooling build-out"
#   .\release.ps1 -Repo Residential-HVAC-Performance-Baseline- -Tag v2026.03.1 -Title "March 2026" -Month 2026-03
#   .\release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026 update" -Draft

param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Title,
    [string]$Month  = "",
    [string]$Notes  = "",
    [switch]$Draft,
    [switch]$SkipValidation
)

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequireGh
. "$PSScriptRoot\repos.ps1"

if ($Repo -notin $Repos) {
    Write-Host "Unknown repo '$Repo'. Valid options:" -ForegroundColor Red
    $Repos | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host ""
Write-Host "RELEASE  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray

# ── Step 1: Validation gate (HVAC baseline repo only) ─────────────────────────
$isHvacRepo = $Repo -eq "Residential-HVAC-Performance-Baseline-"

if ($isHvacRepo -and !$SkipValidation) {
    Write-Host ""
    Write-Host "Step 1 of 3 — Validate HVAC data" -ForegroundColor White

    $validateArgs = @()
    if ($Month -ne "") { $validateArgs += @("-Month", $Month) }

    & "$PSScriptRoot\validate-all.ps1" @validateArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "HALT — validation failed. Release aborted. Fix data errors before tagging." -ForegroundColor Red
        exit 1
    }
} else {
    $reason = if ($SkipValidation) { "(skipped with -SkipValidation)" } else { "(not required for $Repo)" }
    Write-Host ""
    Write-Host "Step 1 of 3 — Validation $reason" -ForegroundColor Gray
}

# ── Step 2: Create release ────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 2 of 3 — Create release $Tag" -ForegroundColor White

$releaseNotes = if ($Notes) { $Notes } else { "$Title." }

$ghArgs = @(
    "release", "create", $Tag,
    "--repo",  "wkcollis1-eng/$Repo",
    "--title", $Title,
    "--notes", $releaseNotes
)
if ($Draft) { $ghArgs += "--draft" }

& gh @ghArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Release creation failed. Tag may already exist — increment patch number." -ForegroundColor Red
    exit 1
}

$draftNote = if ($Draft) { " (draft)" } else { "" }
Write-Host "Release $Tag created$draftNote" -ForegroundColor Green

# Fetch tags locally so git describe --tags reflects the new tag immediately.
# gh release create only writes the tag on GitHub — without this, monthly-update.ps1
# will not find the tag until the next git fetch and will over-count commits.
$repoPathForFetch = "$ReposRoot\$Repo"
if (Test-Path "$repoPathForFetch\.git") {
    Set-Location $repoPathForFetch
    git fetch --tags --quiet 2>$null
    Set-Location $PSScriptRoot
}

# ── Step 3: Push ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 3 of 3 — Push $Repo" -ForegroundColor White

$repoPath = "$ReposRoot\$Repo"
if (Test-Path "$repoPath\.git") {
    Set-Location $repoPath
    git push --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Push failed — tag was created on GitHub but local push failed." -ForegroundColor Yellow
        Write-Host "Run: cd $repoPath && git push" -ForegroundColor Yellow
        Set-Location $PSScriptRoot
        exit 1
    }
    Set-Location $PSScriptRoot
    Write-Host "Pushed." -ForegroundColor Green
}

Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-Host "Release $Tag complete." -ForegroundColor Green
