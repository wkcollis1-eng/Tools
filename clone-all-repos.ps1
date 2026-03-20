# C:\repos\tools\clone-all-repos.ps1
# One-click clone of all managed repos into C:\repos\.
# Safe to re-run — skips repos that already exist locally.

if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed or not on PATH." }

. "$PSScriptRoot\repos.ps1"

$failed = @()

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
            $failed += $repo
        }
    }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) repo(s) failed to clone:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host "Check your network connection and gh auth status, then re-run." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "All repos cloned to $ReposRoot" -ForegroundColor Cyan
}
