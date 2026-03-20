# C:\repos\Tools\create-release.ps1
# Creates a tagged GitHub release using the gh CLI.
# Requires: gh installed and authenticated (gh auth login).
#
# Usage:
#   .\create-release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026 update"
#   .\create-release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026 update" -Draft
#   .\create-release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026 update" -Notes "Custom notes here"
#
# NOTE: For Residential-HVAC-Performance-Baseline- use release.ps1 instead —
# it enforces the HALT-level validation gate before tagging.

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

# ── HVAC baseline repo warning ────────────────────────────────────────────────
# Use release.ps1 instead — it runs the full HALT validation gate before tagging.
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

# ── Auto-fetch latest tag for context and release notes baseline ───────────────
$lastTag = git -C "$ReposRoot\$Repo" describe --tags --abbrev=0 2>$null
if ($lastTag) {
    Write-Host "Latest tag in ${Repo}: $lastTag" -ForegroundColor DarkGray
}

# ── Build release notes ────────────────────────────────────────────────────────
# If -Notes not supplied, auto-generate from git log since the last tag.
# If there is no prior tag, list all commits on the branch.
$releaseNotes = $Notes
if ($releaseNotes -eq "") {
    if ($lastTag) {
        $logLines = git -C "$ReposRoot\$Repo" log --oneline "${lastTag}..HEAD" 2>$null
    } else {
        $logLines = git -C "$ReposRoot\$Repo" log --oneline 2>$null
    }
    if ($logLines) {
        $releaseNotes = ($logLines | ForEach-Object { "- $_" }) -join "`n"
        Write-Host "Auto-generated release notes from git log:" -ForegroundColor DarkGray
        Write-Host $releaseNotes -ForegroundColor DarkGray
    } else {
        $releaseNotes = "$Title."
    }
}

# ── Create the release ─────────────────────────────────────────────────────────
$ghArgs = @(
    "release", "create", $Tag,
    "--repo", "wkcollis1-eng/$Repo",
    "--title", $Title,
    "--notes", $releaseNotes
)

if ($Draft) { $ghArgs += "--draft" }

Write-Host "Creating release $Tag in $Repo..." -ForegroundColor Green
& gh @ghArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "Release creation failed. Tag may already exist — use a new patch number." -ForegroundColor Red
    exit 1
}

# ── Pull the new tag back locally ─────────────────────────────────────────────
# Without this, git describe --tags returns stale results in subsequent scripts
# (monthly-update.ps1, verify-system.ps1, etc.)
Write-Host "Fetching tags locally..." -ForegroundColor DarkGray
git -C "$ReposRoot\$Repo" fetch --tags --quiet

Write-Host "Release $Tag created$(if ($Draft) { ' (draft)' } else { '' })." -ForegroundColor Cyan
