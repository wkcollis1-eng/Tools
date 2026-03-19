# C:\repos\tools\create-issue.ps1
# Opens a GitHub issue in one of the managed repos.
# Requires: gh CLI installed and authenticated (gh auth login)
#
# Usage:
#   .\create-issue.ps1 -Repo home-assistant-config -Title "Fix DST in climate_norms_today.py"
#   .\create-issue.ps1 -Repo Residential-HVAC-Performance-Baseline- -Title "Add March 2026 data" -OpenInBrowser
#   .\create-issue.ps1 -Repo home-assistant-config -Title "Cooling build-out" -BodyFile "C:\repos\tools\issue_body.md"

param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Title,
    [string]$Body = "",
    [string]$BodyFile = "",
    [switch]$OpenInBrowser
)

if (!(Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh CLI is not installed or not on PATH. See https://cli.github.com" }

. "$PSScriptRoot\repos.ps1"

if ($Repo -notin $Repos) {
    Write-Host "Unknown repo '$Repo'. Valid options:" -ForegroundColor Red
    $Repos | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# Build the gh command arguments
$ghArgs = @("issue", "create", "--repo", "wkcollis1-eng/$Repo", "--title", $Title)

if ($BodyFile -ne "") {
    if (-not (Test-Path $BodyFile)) {
        Write-Host "Body file not found: $BodyFile" -ForegroundColor Red
        exit 1
    }
    $ghArgs += @("--body-file", $BodyFile)
} elseif ($Body -ne "") {
    $ghArgs += @("--body", $Body)
} else {
    # No body provided — open editor (gh default behavior)
    Write-Host "No -Body or -BodyFile provided. gh will open your editor..." -ForegroundColor Yellow
}

Write-Host "Creating issue in wkcollis1-eng/$Repo..." -ForegroundColor Green
$issueUrl = & gh @ghArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "gh issue create failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

Write-Host "Issue created: $issueUrl" -ForegroundColor Cyan

if ($OpenInBrowser) {
    Start-Process $issueUrl
}
