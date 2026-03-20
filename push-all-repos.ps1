# C:\repos\tools\push-all-repos.ps1
# Runs git push in every managed repo.
# Warns if a repo is not on main — does not abort (allows intentional branch pushes).
# Run status-all-repos.ps1 first to confirm what will be pushed.

. "$PSScriptRoot\common.ps1"
Assert-Environment

. "$PSScriptRoot\repos.ps1"

$results = @{}

foreach ($repo in $Repos) {
    $path = "$ReposRoot\$repo"

    if (!(Test-Path "$path\.git")) {
        Write-Host "[$repo] Not cloned — skipping" -ForegroundColor Yellow
        $results[$repo] = "not cloned"
        continue
    }

    Set-Location $path

    # Branch check — warn but do not abort
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($branch -ne "main") {
        Write-Host "[$repo] WARNING: pushing branch '$branch' (not main)" -ForegroundColor Yellow
    }

    # Check for unpushed commits
    $unpushed = git rev-list "@{u}..HEAD" --count 2>$null
    if ($unpushed -eq "0" -or $unpushed -eq $null) {
        $results[$repo] = "nothing to push"
        continue
    }

    git push --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$repo] FAILED" -ForegroundColor Red
        $results[$repo] = "failed"
    } else {
        $results[$repo] = "pushed ($unpushed commit(s))"
    }
}

Set-Location "$ReposRoot\tools"

# Summary
Write-Host ""
Write-Host "PUSH SUMMARY" -ForegroundColor Cyan
$anyFailed = $false
foreach ($repo in $Repos) {
    $status = $results[$repo]
    $color  = switch -Wildcard ($status) {
        "pushed*"         { "Green" }
        "nothing to push" { "Gray" }
        "failed"          { "Red"; $anyFailed = $true }
        default           { "Yellow" }
    }
    Write-Host "  $repo — $status" -ForegroundColor $color
}

if ($anyFailed) { exit 1 }
