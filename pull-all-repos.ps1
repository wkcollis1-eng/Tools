# C:\repos\Tools\pull-all-repos.ps1
# Runs git pull in every managed repo.
# Warns (does not abort) if a repo is not on main.
# Run this at the start of every session before opening Claude Code.
#
# Exit codes:
#   0 — all repos succeeded (updated or already up to date)
#   1 — one or more repos failed to pull

. "$PSScriptRoot\common.ps1"
Assert-Environment

. "$PSScriptRoot\repos.ps1"

$results  = @{}
$diffStats = @{}

foreach ($repo in $Repos) {
    $path = $RepoMap[$repo].Path

    if (!(Test-Path "$path\.git")) {
        Write-Host "[$repo] Not cloned — skipping (run clone-all-repos.ps1)" -ForegroundColor Yellow
        $results[$repo] = "not cloned"
        continue
    }

    Set-Location $path

    # Branch check — warn but do not abort (legitimate feature branch work is possible)
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($branch -ne "main") {
        Write-Host "[$repo] WARNING: on branch '$branch' (expected main)" -ForegroundColor Yellow
    }

    $before = git rev-parse HEAD 2>$null

    # --ff-only surfaces diverged branches instead of silently creating merge commits
    git pull --ff-only --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$repo] FAILED (merge conflict, diverged branch, or network error)" -ForegroundColor Red
        Write-Host "  Hint: run 'git status' in $path to diagnose" -ForegroundColor DarkGray
        $results[$repo] = "failed"
        continue
    }

    $after = git rev-parse HEAD 2>$null

    if ($before -ne $after) {
        $results[$repo] = "updated"
        # Capture diff stats for updated repos
        $stat = git diff --stat "$before..$after" 2>$null | Select-Object -Last 1
        if ($stat) { $diffStats[$repo] = $stat.Trim() }
    } else {
        $results[$repo] = "up to date"
    }
}

Set-Location $PSScriptRoot

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "PULL SUMMARY" -ForegroundColor Cyan

$anyFailed = $false

foreach ($repo in $Repos) {
    $status = $results[$repo]

    # Track failure separately — do NOT embed side-effects inside switch expression
    if ($status -eq "failed") { $anyFailed = $true }

    $color = switch ($status) {
        "updated"    { "Green" }
        "up to date" { "Gray" }
        "failed"     { "Red" }
        "not cloned" { "Yellow" }
        default      { "Yellow" }
    }

    Write-Host "  $repo — $status" -ForegroundColor $color

    # Show diff stats when available
    if ($diffStats.ContainsKey($repo)) {
        Write-Host "    $($diffStats[$repo])" -ForegroundColor DarkGray
    }
}

Write-Host ""

if ($anyFailed) {
    Write-Host "One or more repos failed to pull. See above for details." -ForegroundColor Red
    exit 1
}
