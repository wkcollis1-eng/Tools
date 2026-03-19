# C:\repos\tools\status-all-repos.ps1
# Runs git status --short in every managed repo.
# Also shows current branch and unpushed commit count.
# Use before committing or pushing for a quick sanity check.

if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed or not on PATH." }

. "$PSScriptRoot\repos.ps1"

foreach ($repo in $Repos) {
    $path = "$ReposRoot\$repo"

    if (!(Test-Path "$path\.git")) {
        Write-Host ""
        Write-Host "=== $repo ===" -ForegroundColor Yellow
        Write-Host "  Not cloned" -ForegroundColor Yellow
        continue
    }

    Set-Location $path

    $branch   = git rev-parse --abbrev-ref HEAD 2>$null
    $unpushed = git rev-list "@{u}..HEAD" --count 2>$null
    $changes  = git status --short

    $branchColor = if ($branch -eq "main") { "Cyan" } else { "Yellow" }

    Write-Host ""
    Write-Host "=== $repo ===" -ForegroundColor Cyan
    Write-Host "  Branch  : $branch" -ForegroundColor $branchColor
    Write-Host "  Unpushed: $unpushed commit(s)" -ForegroundColor $(if ([int]$unpushed -gt 0) { "Yellow" } else { "Gray" })

    if ($changes) {
        Write-Host "  Changes :" -ForegroundColor Yellow
        foreach ($line in $changes) {
            $color = if ($line -match "^\?\?") { "Gray" }
                     elseif ($line -match "^M|^A|^D") { "Green" }
                     else { "Yellow" }
            Write-Host "    $line" -ForegroundColor $color
        }
    } else {
        Write-Host "  Changes : none" -ForegroundColor Gray
    }
}

Set-Location "$ReposRoot\tools"
Write-Host ""
