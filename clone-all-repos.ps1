# C:\repos\Tools\clone-all-repos.ps1
# One-click clone of all managed repos into C:\repos\.
# Safe to re-run — skips repos that already exist locally.
#
# Usage:
#   .\clone-all-repos.ps1             # standard
#   .\clone-all-repos.ps1 -Shallow    # --depth 1 (faster, less history)

param(
    [switch]$Shallow
)

if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed or not on PATH." }

. "$PSScriptRoot\repos.ps1"

$failed   = @()
$total    = $Repos.Count
$current  = 0

foreach ($repo in $Repos) {
    $current++
    $path = "$ReposRoot\$repo"
    $url  = $RepoUrls[$repo]

    # Progress bar
    $pct = [int](($current - 1) / $total * 100)
    Write-Progress -Activity "Cloning repos" -Status "$repo ($current of $total)" -PercentComplete $pct

    if (Test-Path "$path\.git") {
        Write-Host "  SKIP  $repo — already cloned" -ForegroundColor DarkGray
    } elseif (Test-Path $path) {
        Write-Host "  SKIP  $repo — directory exists but is not a git repo (inspect manually)" -ForegroundColor Yellow
    } else {
        Write-Host "  Cloning $repo..." -ForegroundColor Green
        $cloneArgs = @("clone", $url, $path)
        if ($Shallow) { $cloneArgs += "--depth", "1" }
        git @cloneArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAIL  $repo" -ForegroundColor Red
            $failed += $repo
        } else {
            # Unblock all PS1 scripts in the newly cloned repo so they can be
            # executed without "downloaded from the internet" prompts.
            Get-ChildItem (Join-Path $path "*.ps1") -ErrorAction SilentlyContinue |
                Unblock-File
            Write-Host "  OK    $repo (scripts unblocked)" -ForegroundColor Green
        }
    }
}

Write-Progress -Activity "Cloning repos" -Completed

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) repo(s) failed to clone:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host "Check your network connection and gh auth status, then re-run." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "All repos cloned to $ReposRoot" -ForegroundColor Cyan
}
