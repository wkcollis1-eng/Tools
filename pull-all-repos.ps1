# C:\repos\Tools\pull-all-repos.ps1
# Runs git pull --ff-only in every managed repo.
# Warns (does not abort) on per-repo failure — soft failure model.
# Exits 1 only if ALL eligible repos failed (network-down scenario).
# Run at the start of every session before opening Claude Code.

. "$PSScriptRoot\common.ps1"
Assert-Environment
. "$PSScriptRoot\repos.ps1"

$results  = @{}
$eligible = 0   # repos that exist locally and were attempted

foreach ($repo in $Repos) {
    $path = $RepoMap[$repo].Path

    if (!(Test-GitRepo $path)) {
        Write-Host "[$repo] Not cloned — skipping (run: .\clone-all-repos.ps1)" -ForegroundColor Yellow
        $results[$repo] = "not cloned"
        continue
    }

    $eligible++

    # Branch check — warn but do not abort (legitimate feature branch work is allowed)
    $branch = (git -C $path rev-parse --abbrev-ref HEAD 2>$null)
    $branch = if ($branch) { $branch.Trim() } else { "unknown" }
    if ($branch -ne "main") {
        Write-Host "[$repo] WARNING: on branch '$branch' (expected main)" -ForegroundColor Yellow
    }

    $before = (git -C $path rev-parse HEAD 2>$null)

    # --ff-only: surfaces diverged branches instead of silently creating merge commits
    git -C $path pull --ff-only --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$repo] Pull failed — branch may have diverged or network unreachable." -ForegroundColor Yellow
        Write-Host "       Run: cd $path && git status" -ForegroundColor Gray
        $results[$repo] = "failed"
        continue
    }

    $after = (git -C $path rev-parse HEAD 2>$null)

    if ($before -ne $after) {
        # Diff stats for the incoming changes
        $diffStats = git -C $path diff --stat "$before..HEAD" 2>$null
        $statsInfo = ""
        if ($diffStats -match '(\d+) files? changed.*?(\d+) insertions?.*?(\d+) deletions?') {
            $statsInfo = " ($($Matches[1]) files, +$($Matches[2]) -$($Matches[3]))"
        }
        Write-Host "[$repo] Updated$statsInfo" -ForegroundColor Green
        $results[$repo] = "updated$statsInfo"
    } else {
        Write-Host "[$repo] Up to date" -ForegroundColor Gray
        $results[$repo] = "up to date"
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "PULL SUMMARY" -ForegroundColor Cyan

foreach ($repo in $Repos) {
    $status = $results[$repo]
    $color  = switch -Wildcard ($status) {
        "updated*"    { "Green"  }
        "up to date"  { "Gray"   }
        "failed"      { "Red"    }
        "not cloned"  { "Yellow" }
        default       { "Yellow" }
    }
    Write-Host "  $repo — $status" -ForegroundColor $color
}

# Hard exit only if ALL eligible repos failed — indicates network/environment issue.
# Individual per-repo failures remain soft (session can proceed with caution).
$failedCount = ($results.Values | Where-Object { $_ -eq "failed" }).Count
if ($eligible -gt 0 -and $failedCount -eq $eligible) {
    Write-Host ""
    Write-Host "All repos failed to pull — check network and gh auth, then retry." -ForegroundColor Red
    exit 1
}
