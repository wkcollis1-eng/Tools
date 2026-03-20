# C:\repos\Tools\pull-all-repos.ps1
# Runs git pull in every managed repo.
# Warns (does not abort) if a repo is not on main.
# Run this at the start of every session before opening Claude Code.



. "$PSScriptRoot\common.ps1"
Assert-Environment

. "$PSScriptRoot\repos.ps1"

$results = @{}

foreach ($repo in $Repos) {
    $path = "$ReposRoot\$repo"

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
    git pull --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$repo] FAILED (merge conflict or network error)" -ForegroundColor Red
        $results[$repo] = "failed"
        continue
    }
    $after = git rev-parse HEAD 2>$null

    if ($before -ne $after) {
        $results[$repo] = "updated"
    } else {
        $results[$repo] = "up to date"
    }
}

Set-Location $PSScriptRoot

# Summary
Write-Host ""
Write-Host "PULL SUMMARY" -ForegroundColor Cyan
$anyFailed = $false
foreach ($repo in $Repos) {
    $status = $results[$repo]
    $color  = switch ($status) {
        "updated"    { "Green" }
        "up to date" { "Gray" }
        "failed"     { "Red"; $anyFailed = $true }
        default      { "Yellow" }
    }
    Write-Host "  $repo — $status" -ForegroundColor $color
}

if ($anyFailed) { exit 1 }
