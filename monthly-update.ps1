# C:\repos\tools\monthly-update.ps1
# Orchestrates the full 1st-of-month data update workflow:
#   1. Pull all repos
#   2. Validate HVAC baseline data (HALT stops the sequence)
#   3. Open an issue in the target repo as a work queue item (optional)
#   4. After Claude Code session: validate again, tag releases, push
#
# This script is designed to be run in two phases:
#   Phase 1 (before Claude Code session): pull + validate + create-issue
#   Phase 2 (after Claude Code session):  validate + release + push
#
# Usage:
#   .\monthly-update.ps1 -Month 2026-03 -Phase 1
#   .\monthly-update.ps1 -Month 2026-03 -Phase 2 -Tag v2026.03.1
#   .\monthly-update.ps1 -Month 2026-03 -Phase 2 -Tag v2026.03.1 -SkipRelease

param(
    [Parameter(Mandatory)][string]$Month,
    [Parameter(Mandatory)][ValidateSet("1","2")][string]$Phase,
    [string]$Tag = "",
    [switch]$SkipRelease,
    [switch]$DraftRelease
)

if (!(Get-Command git -ErrorAction SilentlyContinue))    { throw "git is not installed or not on PATH." }
if (!(Get-Command gh  -ErrorAction SilentlyContinue))    { throw "gh CLI is not installed or not on PATH. See https://cli.github.com" }
if (!(Get-Command python -ErrorAction SilentlyContinue)) { throw "python is not installed or not on PATH." }

. "$PSScriptRoot\repos.ps1"

# Normalize month to YYYY-MM
if ($Month -match '^\d{4}-\d{2}-\d{2}$') {
    $Month = $Month.Substring(0, 7)
}
if ($Month -notmatch '^\d{4}-\d{2}$') {
    Write-Host "Invalid month format '$Month'. Use YYYY-MM." -ForegroundColor Red
    exit 1
}

$monthDisplay = $Month   # e.g. 2026-03
$year  = $Month.Split('-')[0]
$mo    = $Month.Split('-')[1]

# Repos that receive a release tag on Phase 2
$releaseRepos = @(
    "home-assistant-config",
    "Residential-HVAC-Performance-Baseline-",
    "Lifepo4-Battery-Banks",
    "DIY-LiFePO4-UPS"
)

# ─────────────────────────────────────────────────────────────────────────────
function Step($msg) {
    Write-Host ""
    Write-Host "── $msg" -ForegroundColor Cyan
}

function Abort($msg) {
    Write-Host ""
    Write-Host "ABORTED: $msg" -ForegroundColor Red
    exit 1
}

function RunValidation($monthArg) {
    Step "Validating HVAC baseline data ($monthArg)"
    & "$PSScriptRoot\validate-all.ps1" -Month $monthArg
    if ($LASTEXITCODE -ne 0) {
        Abort "Validation HALT — fix data errors before proceeding."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1 — Pull, validate prior month data, open issue
# ─────────────────────────────────────────────────────────────────────────────
if ($Phase -eq "1") {
    Write-Host ""
    Write-Host "Monthly Update — Phase 1 ($monthDisplay)" -ForegroundColor White

    Step "Pulling all repos"
    & "$PSScriptRoot\pull-all-repos.ps1"

    Step "Checking git status before session"
    & "$PSScriptRoot\status-all-repos.ps1"

    # Validate the month being entered (data may be partially present)
    RunValidation $monthDisplay

    Step "Creating work queue issue"
    $issueTitle = "Monthly data update — $monthDisplay"
    $issueBody  = "Monthly utility bill entry and data update for $monthDisplay.`n`nChecklist:`n- [ ] Enter gas bill (monthly_gas_scg.csv)`n- [ ] Enter electricity bill (monthly_electricity_eversource.csv)`n- [ ] Enter DHW reading (monthly_dhw_navien.csv)`n- [ ] Update monthly_summary.csv`n- [ ] Update monthly_hvac_runtime.csv`n- [ ] Run validate-all.ps1 -Month $monthDisplay`n- [ ] Commit and tag releases"

    Write-Host "Creating issue in Residential-HVAC-Performance-Baseline-..." -ForegroundColor Green
    $issueUrl = & gh issue create `
        --repo wkcollis1-eng/Residential-HVAC-Performance-Baseline- `
        --title $issueTitle `
        --body $issueBody

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Issue created: $issueUrl" -ForegroundColor Cyan
    } else {
        Write-Host "Issue creation failed (gh error) — continuing." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Phase 1 complete. Run your Claude Code session now." -ForegroundColor White
    Write-Host "When done, run: .\monthly-update.ps1 -Month $monthDisplay -Phase 2 -Tag v$year.$mo.1" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 — Validate after session, tag releases, push
# ─────────────────────────────────────────────────────────────────────────────
if ($Phase -eq "2") {
    Write-Host ""
    Write-Host "Monthly Update — Phase 2 ($monthDisplay)" -ForegroundColor White

    if (-not $SkipRelease -and $Tag -eq "") {
        Abort "-Tag is required for Phase 2 unless -SkipRelease is set. Example: -Tag v$year.$mo.1"
    }

    Step "Checking git status after session"
    & "$PSScriptRoot\status-all-repos.ps1"

    # Clean working tree guard — uncommitted changes before tagging/pushing is an error
    foreach ($repo in $releaseRepos) {
        $path = "$ReposRoot\$repo"
        if (!(Test-Path "$path\.git")) { continue }
        Set-Location $path
        $dirty = git status --porcelain
        if ($dirty) {
            Set-Location "$ReposRoot\tools"
            Abort "Uncommitted changes in $repo. Commit or stash before running Phase 2."
        }
    }
    Set-Location "$ReposRoot\tools"

    # Validate the freshly entered month
    RunValidation $monthDisplay

    if (-not $SkipRelease) {
        Step "Creating releases ($Tag)"

        $releaseTitle = "$monthDisplay monthly update"
        $releaseArgs  = @("release", "create", $Tag, "--title", $releaseTitle, "--notes", "Monthly data update for $monthDisplay.")
        if ($DraftRelease) { $releaseArgs += "--draft" }

        foreach ($repo in $releaseRepos) {
            $repoPath = "$ReposRoot\$repo"
            if (-not (Test-Path "$repoPath\.git")) {
                Write-Host "Skipping $repo (not cloned locally)" -ForegroundColor Yellow
                continue
            }
            # Only release repos with commits since last tag
            Set-Location $repoPath
            $lastTag = git describe --tags --abbrev=0 2>$null
            $commitsSince = if ($lastTag) { git rev-list "$lastTag..HEAD" --count } else { "1" }
            if ([int]$commitsSince -gt 0) {
                Write-Host "  Tagging $repo..." -ForegroundColor Green
                & gh @(@("release", "create", $Tag) + @("--repo", "wkcollis1-eng/$repo") + @("--title", $releaseTitle) + @("--notes", "Monthly data update for $monthDisplay.") + $(if ($DraftRelease) { @("--draft") } else { @() }))
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  Release failed for $repo (tag may already exist)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  Skipping $repo (no new commits since $lastTag)" -ForegroundColor Yellow
            }
        }
        Set-Location "$ReposRoot\tools"
    }

    Step "Pushing all repos"
    & "$PSScriptRoot\push-all-repos.ps1"

    Write-Host ""
    Write-Host "Phase 2 complete. Monthly update for $monthDisplay finished." -ForegroundColor White
}
