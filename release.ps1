# C:\repos\Tools\release.ps1
# Creates a tagged GitHub release with a validation gate for the HVAC baseline repo.
# For Residential-HVAC-Performance-Baseline-, runs validate-all.ps1 first —
# a HALT stops the release. For all other repos, tags immediately.
# Validates CalVer tag format before any GitHub call.
# Auto-generates release notes from git log if -Notes not supplied.
# Fetches the new tag locally after creation so git describe is immediately accurate.
#
# Usage:
#   .\release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026"
#   .\release.ps1 -Repo Residential-HVAC-Performance-Baseline- -Tag v2026.03.1 -Title "March 2026" -Month 2026-03
#   .\release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026" -Draft

param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Title,
    [string]$Month          = "",
    [string]$Notes          = "",
    [switch]$Draft,
    [switch]$SkipValidation
)

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequireGh
. "$PSScriptRoot\repos.ps1"

# ── Repo validation ────────────────────────────────────────────────────────────
if ($Repo -notin $Repos) {
    Write-Host "Unknown repo '$Repo'. Valid options:" -ForegroundColor Red
    $Repos | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# ── CalVer tag format validation ───────────────────────────────────────────────
if ($Tag -notmatch '^v\d{4}\.\d{2}\.\d+$') {
    Write-Host "Invalid tag format: '$Tag'" -ForegroundColor Red
    Write-Host "Expected CalVer format: vYYYY.MM.N  (e.g. v2026.03.1)" -ForegroundColor Yellow
    exit 1
}

$repoPath = $RepoMap[$Repo].Path

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
    $reason = if ($SkipValidation) { "(skipped — -SkipValidation)" } else { "(not required for $Repo)" }
    Write-Host ""
    Write-Host "Step 1 of 3 — Validation $reason" -ForegroundColor DarkGray
}

# ── Step 2: Build release notes and create release ────────────────────────────
Write-Host ""
Write-Host "Step 2 of 3 — Create release $Tag" -ForegroundColor White

if (!$Notes) {
    if (Test-GitRepo $repoPath) {
        $lastTag = (git -C $repoPath describe --tags --abbrev=0 "HEAD~1" 2>$null)
        $lastTag = if ($lastTag) { $lastTag.Trim() } else { $null }

        if ($lastTag) {
            $gitRange   = "$lastTag..HEAD"
            $rangeNote  = "(since $lastTag)"
        } else {
            $firstCommit = (git -C $repoPath rev-list --max-parents=0 HEAD 2>$null).Trim()
            $gitRange    = "$firstCommit..HEAD"
            $rangeNote   = "(initial release)"
        }

        $commitLog = git -C $repoPath log --oneline $gitRange 2>$null
        if ($commitLog) {
            $noteLines = $commitLog -split "`n" | Where-Object { $_.Trim() } |
                         ForEach-Object { "- $_" }
            $Notes = "$Title`n`n## Changes $rangeNote`n`n" + ($noteLines -join "`n")
        } else {
            $Notes = "$Title."
        }
    } else {
        $Notes = "$Title."
    }
}

$ghArgs = @(
    "release", "create", $Tag,
    "--repo",  "wkcollis1-eng/$Repo",
    "--title", $Title,
    "--notes", $Notes
)
if ($Draft) { $ghArgs += "--draft" }

& gh @ghArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Release creation failed. Tag may already exist — increment patch number." -ForegroundColor Red
    exit 1
}

Write-Host "Release $Tag created$(if ($Draft) { ' (draft)' })." -ForegroundColor Green

# Pull the new tag back locally immediately so git describe returns correct results
# in subsequent monthly-update.ps1 and verify-system.ps1 calls.
if (Test-GitRepo $repoPath) {
    git -C $repoPath fetch --tags --quiet 2>$null
}

# ── Step 3: Push ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 3 of 3 — Push $Repo" -ForegroundColor White

if (Test-GitRepo $repoPath) {
    git -C $repoPath push --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Push failed — tag was created on GitHub but local push failed." -ForegroundColor Yellow
        Write-Host "Run: git -C `"$repoPath`" push" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Pushed." -ForegroundColor Green
}

Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-Host "Release $Tag complete." -ForegroundColor Green
