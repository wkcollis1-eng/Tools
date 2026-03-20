# C:\repos\Tools\push-all-repos.ps1
# Runs git push in every managed repo.
# Warns if a repo is not on main — does not abort (allows intentional branch pushes).
# Auto-stashes dirty working tree before push and pops on completion.
# Warns on non-conventional commit messages (informational only).
# Run status-all-repos.ps1 first to confirm what will be pushed.

. "$PSScriptRoot\common.ps1"
Assert-Environment
. "$PSScriptRoot\repos.ps1"

function Test-ConventionalCommit([string]$message) {
    return $message -match '^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)(\(.+\))?: .{1,}'
}

$results  = @{}
$anyFailed = $false

foreach ($repo in $Repos) {
    $path = $RepoMap[$repo].Path

    if (!(Test-GitRepo $path)) {
        Write-Host "[$repo] Not cloned — skipping" -ForegroundColor Yellow
        $results[$repo] = "not cloned"
        continue
    }

    # Branch check — warn but do not abort
    $branch = (git -C $path rev-parse --abbrev-ref HEAD 2>$null)
    $branch = if ($branch) { $branch.Trim() } else { "unknown" }
    if ($branch -ne "main") {
        Write-Host "[$repo] WARNING: pushing branch '$branch' (not main)" -ForegroundColor Yellow
    }

    # Check for no upstream tracking branch before attempting anything
    $null = git -C $path rev-parse --verify "@{u}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$repo] No upstream branch — run: git -C $path push --set-upstream origin $branch" -ForegroundColor Yellow
        $results[$repo] = "no upstream"
        continue   # FIX: was 'return' which exited the entire script
    }

    # Check for unpushed commits
    $unpushedRaw = git -C $path rev-list "@{u}..HEAD" --count 2>$null
    $unpushed    = [int]($unpushedRaw.Trim() -as [int])
    if ($unpushed -eq 0) {
        $results[$repo] = "nothing to push"
        continue   # FIX: was 'return' which exited the entire script
    }

    # Warn on non-conventional commit messages (informational only — does not block)
    $recentMsgs = git -C $path log --format="%s" -n 10 2>$null
    if ($recentMsgs) {
        $nonConventional = $recentMsgs -split "`n" |
            Where-Object { $_ -and !(Test-ConventionalCommit $_) }
        if ($nonConventional.Count -gt 0) {
            Write-Host "[$repo] WARNING: non-conventional commit message(s):" -ForegroundColor Yellow
            $nonConventional | Select-Object -First 3 |
                ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
            if ($nonConventional.Count -gt 3) {
                Write-Host "    ... and $($nonConventional.Count - 3) more" -ForegroundColor Gray
            }
        }
    }

    # Auto-stash dirty working tree so push isn't blocked by uncommitted changes
    $dirty   = git -C $path status --porcelain 2>$null
    $stashed = $false
    if ($dirty) {
        Write-Host "[$repo] Stashing dirty working tree before push..." -ForegroundColor Yellow
        git -C $path stash push -m "auto-stash before push-all-repos" 2>$null
        $stashed = ($LASTEXITCODE -eq 0)
        if (!$stashed) {
            Write-Host "[$repo] WARNING: stash failed — pushing with dirty tree" -ForegroundColor Yellow
        }
    }

    try {
        git -C $path push --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[$repo] FAILED to push" -ForegroundColor Red
            $results[$repo] = "failed"
            $anyFailed = $true
        } else {
            $results[$repo] = "pushed ($unpushed commit(s))"
        }
    } finally {
        # Always restore stash even if push failed
        if ($stashed) {
            git -C $path stash pop 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[$repo] WARNING: stash pop failed — check git stash list in $path" -ForegroundColor Yellow
            }
        }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "PUSH SUMMARY" -ForegroundColor Cyan

foreach ($repo in $Repos) {
    $status = $results[$repo]
    $color  = switch -Wildcard ($status) {
        "pushed*"          { "Green"  }
        "nothing to push"  { "Gray"   }
        "no upstream"      { "Yellow" }
        "failed"           { "Red"    }
        default            { "Yellow" }
    }
    Write-Host "  $repo — $status" -ForegroundColor $color
}

if ($anyFailed) { exit 1 }
