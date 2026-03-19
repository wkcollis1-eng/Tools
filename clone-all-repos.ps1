# C:\repos\tools\clone-all-repos.ps1
# One-click clone of all managed repos into C:\repos\.
# Safe to re-run — skips repos that already exist locally.

if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed or not on PATH." }

. "$PSScriptRoot\repos.ps1"

foreach ($repo in $Repos) {
    $path = "$ReposRoot\$repo"
    $url  = $RepoUrls[$repo]

    if (Test-Path $path) {
        Write-Host "Already exists: $repo" -ForegroundColor Yellow
    } else {
        Write-Host "Cloning $repo..." -ForegroundColor Green
        git clone $url $path
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAILED to clone $repo" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "All repos cloned to $ReposRoot" -ForegroundColor Cyan
