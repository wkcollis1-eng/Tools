# C:\repos\Tools\push-all-repos.ps1
# Runs git push in every managed repo.
# Warns if a repo is not on main — does not abort (allows intentional branch pushes).
# Run status-all-repos.ps1 first to confirm what will be pushed.
#
# Exit codes:
#   0 — all repos succeeded (pushed or nothing to push)
#   1 — one or more repos failed to push (including missing upstream)

. "$PSScriptRoot\common.ps1"
Assert-Environment

. "$PSScriptRoot\repos.ps1"

$results  = @{}
$anyFailed = $false

foreach ($repo in $Repos) {
    $path = $RepoMap[$repo].Path

    if (!(Test-Path "$path\.git")) {
        Write-Host "[$repo] Not cloned — skipping" -ForegroundColor Yellow
        $results[$repo] = "not cloned"
        continue
    }

    Set-Location $path

    # Branch check — warn but do not abort (allows intentional branch pushes)
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($branch -ne "main") {
        Write-Host "[$repo] WARNING: pushing branch '$branch' (not main)" -ForegroundColor Yellow
    }

    # Detect missing upstream tracking branch before attempting rev-list
    $upstream = git rev-parse --abbrev-ref "@{u}" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $upstream) {
        Write-Host "[$repo] No upstream tracking branch." -ForegroundColor Yellow
        Write-Host "  Run: git push --set-upstream origin $branch" -ForegroundColor Yellow
        $results[$repo] = "no upstream"
        $anyFailed = $true
        continue
    }

    # Count unpushed commits (safe — upstream confirmed above)
    $unpushed = git rev-list "@{u}..HEAD" --count 2>$null
    $unpushedCount = [int]($unpushed -as [int])

    if ($unpushedCount -eq 0) {
        $results[$repo] = "nothing to push"
        continue
    }

    git push --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$repo] PUSH FAILED" -ForegroundColor Red
        $results[$repo] = "failed"
        $anyFailed = $true
    } else {
        $results[$repo] = "pushed ($unpushedCount commit(s))"
    }
}

Set-Location $RepoMap["Tools"].Path

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "PUSH SUMMARY" -ForegroundColor Cyan

foreach ($repo in $Repos) {
    $status = $results[$repo]

    # Determine display color — do NOT embed $anyFailed side-effect inside switch expression
    $color = switch -Wildcard ($status) {
        "pushed*"         { "Green" }
        "nothing to push" { "Gray" }
        "failed"          { "Red" }
        "no upstream"     { "Yellow" }
        default           { "Yellow" }
    }

    Write-Host "  $repo — $status" -ForegroundColor $color
}

Write-Host ""

if ($anyFailed) {
    Write-Host "One or more repos failed or need upstream setup. See above." -ForegroundColor Red
    exit 1
}
