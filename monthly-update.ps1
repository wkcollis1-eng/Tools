# C:\repos\Tools\monthly-update.ps1
# Orchestrates the full 1st-of-month data update workflow:
#   1. Pull all repos
#   2. Validate HVAC baseline data for the PRIOR month (HALT stops the sequence)
#   3. Open an issue in the target repo as a work queue item (optional)
#   4. After Claude Code session: validate current month, tag releases, push
#
# This script is designed to be run in two phases:
#   Phase 1 (before Claude Code session): pull + validate prior month + create-issue
#   Phase 2 (after Claude Code session):  validate current month + release + push
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

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequireGh -RequirePython

. "$PSScriptRoot\repos.ps1"

# ── Month format validation ────────────────────────────────────────────────────
if ($Month -match '^\d{4}-\d{2}-\d{2}$') {
    $Month = $Month.Substring(0, 7)
}
if ($Month -notmatch '^\d{4}-\d{2}$') {
    Write-Host "Invalid month format '$Month'. Use YYYY-MM." -ForegroundColor Red
    exit 1
}

$monthDisplay = $Month
$year  = $Month.Split('-')[0]
$mo    = $Month.Split('-')[1]

# Compute the prior calendar month (used for Phase 1 validation against existing data)
$monthDate  = [datetime]::ParseExact($Month, "yyyy-MM", $null)
$priorMonth = $monthDate.AddMonths(-1).ToString("yyyy-MM")

# Repos that receive a release tag on Phase 2 — all repos except Tools itself.
$releaseRepos = $Repos | Where-Object { $_ -ne "Tools" }

# ── Helpers ───────────────────────────────────────────────────────────────────
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

# ── CalVer tag format validation (Phase 2 only) ────────────────────────────────
if ($Phase -eq "2" -and -not $SkipRelease -and $Tag -ne "") {
    if ($Tag -notmatch '^v\d{4}\.\d{2}\.\d+$') {
        Write-Host "Invalid tag format: '$Tag'" -ForegroundColor Red
        Write-Host "Expected CalVer format: vYYYY.MM.N  (e.g. v$year.$mo.1)" -ForegroundColor Yellow
        exit 1
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 1 — Pull, validate PRIOR month's existing data, open work queue issue
# ═════════════════════════════════════════════════════════════════════════════
if ($Phase -eq "1") {
    Write-Host ""
    Write-Host "Monthly Update — Phase 1 ($monthDisplay)" -ForegroundColor White

    Step "Pulling all repos"
    & "$PSScriptRoot\pull-all-repos.ps1"

    Step "Checking git status before session"
    & "$PSScriptRoot\status-all-repos.ps1"

    # Validate the PRIOR month's data (current month data doesn't exist yet).
    # This confirms the baseline is clean before beginning new entry work.
    RunValidation $priorMonth

    Step "Creating work queue issue"
    $issueTitle = "Monthly data update — $monthDisplay"
    $issueBody  = @"
Monthly utility bill entry and data update for $monthDisplay.

Checklist:
- [ ] Enter gas bill (monthly_gas_scg.csv)
- [ ] Enter electricity bill (monthly_electricity_eversource.csv)
- [ ] Enter DHW reading (monthly_dhw_navien.csv)
- [ ] Update monthly_summary.csv
- [ ] Update monthly_hvac_runtime.csv
- [ ] Run validate-all.ps1 -Month $monthDisplay
- [ ] Commit and tag releases
"@

    Write-Host "Creating issue in Residential-HVAC-Performance-Baseline-..." -ForegroundColor Green
    $issueRaw = & gh issue create `
        --repo wkcollis1-eng/Residential-HVAC-Performance-Baseline- `
        --title $issueTitle `
        --body $issueBody

    # FIX: gh may emit warnings alongside the URL — isolate the URL line only
    $issueUrl = $issueRaw | Where-Object { $_ -match '^https://' } | Select-Object -First 1

    if ($LASTEXITCODE -eq 0 -and $issueUrl) {
        Write-Host "Issue created: $issueUrl" -ForegroundColor Cyan
    } else {
        Write-Host "Issue creation failed or URL not returned (gh error) — continuing." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Phase 1 complete. Run your Claude Code session now." -ForegroundColor White
    Write-Host "When done, run: .\monthly-update.ps1 -Month $monthDisplay -Phase 2 -Tag v$year.$mo.1" -ForegroundColor Yellow
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 2 — Validate after session, tag releases, push
# ═════════════════════════════════════════════════════════════════════════════
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
        if (!(Test-GitRepo $path)) { continue }
        $dirty = git -C $path status --porcelain
        if ($dirty) {
            Abort "Uncommitted changes in $repo. Commit or stash before running Phase 2."
        }
    }

    # Validate the freshly entered month's data
    RunValidation $monthDisplay

    if (-not $SkipRelease) {
        Step "Creating releases ($Tag)"

        $releaseTitle = "$monthDisplay monthly update"
        $releaseNotes = "Monthly data update for $monthDisplay."

        foreach ($repo in $releaseRepos) {
            $repoPath = "$ReposRoot\$repo"
            if (-not (Test-GitRepo $repoPath)) {
                Write-Host "  Skipping $repo (not cloned locally)" -ForegroundColor Yellow
                continue
            }

            # Count commits since the last tag to decide whether this repo needs a release.
            # When no prior tag exists (first release), count all commits on HEAD instead
            # of constructing a malformed "$lastTag..HEAD" range with an empty $lastTag.
            $lastTag     = (git -C $repoPath describe --tags --abbrev=0 2>$null)
            $lastTag     = if ($lastTag) { $lastTag.Trim() } else { $null }
            $commitsSince = if ($lastTag) {
                git -C $repoPath rev-list "$lastTag..HEAD" --count 2>$null
            } else {
                git -C $repoPath rev-list HEAD --count 2>$null
            }
            $commitCount = [int]($commitsSince.Trim() -as [int])

            if ($commitCount -gt 0) {
                $sinceMsg = if ($lastTag) { "$commitCount commit(s) since $lastTag" } else { "$commitCount commit(s) — first release" }
                Write-Host "  Tagging $repo ($sinceMsg)..." -ForegroundColor Green
                $releaseArgs = @(
                    "release", "create", $Tag,
                    "--repo", "wkcollis1-eng/$repo",
                    "--title", $releaseTitle,
                    "--notes", $releaseNotes
                )
                if ($DraftRelease) { $releaseArgs += "--draft" }
                & gh @releaseArgs
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  Release failed for $repo (tag may already exist)" -ForegroundColor Yellow
                } else {
                    # Pull the new tag back locally so git describe stays accurate
                    git -C $repoPath fetch --tags --quiet
                }
            } else {
                $skipMsg = if ($lastTag) { "no new commits since $lastTag" } else { "no commits found" }
                Write-Host "  Skipping $repo ($skipMsg)" -ForegroundColor Yellow
            }
        }
    }

    Step "Pushing all repos"
    & "$PSScriptRoot\push-all-repos.ps1"

    Write-Host ""
    Write-Host ("═" * 50) -ForegroundColor DarkGray
    Write-Host "Phase 2 complete. Monthly update for $monthDisplay finished." -ForegroundColor White
    Write-Host ""
    Write-Host "Reminders:" -ForegroundColor DarkGray
    Write-Host "  - If .py files changed: run .\deploy-to-ha.ps1 then reload HA Shell Commands" -ForegroundColor DarkGray
    Write-Host "  - Check open issues:    .\list-issues.ps1 -Remote -Repo Residential-HVAC-Performance-Baseline-" -ForegroundColor DarkGray
}
