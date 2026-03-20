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

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequireGh

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
    # Write body to temp file and use --body-file to avoid Windows argument
    # escaping issues with backticks, code blocks, and special characters.
    $tmpFile = [System.IO.Path]::GetTempFileName()
    Set-Content $tmpFile $Body -Encoding UTF8
    $ghArgs += @("--body-file", $tmpFile)
} else {
    # No body provided — open editor (gh default behavior)
    Write-Host "No -Body or -BodyFile provided. gh will open your editor..." -ForegroundColor Yellow
}

Write-Host "Creating issue in wkcollis1-eng/$Repo..." -ForegroundColor Green
$issueUrl = & gh @ghArgs

# Clean up temp body file if one was created
if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -ErrorAction SilentlyContinue }

if ($LASTEXITCODE -ne 0) {
    Write-Host "gh issue create failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

Write-Host "Issue created: $issueUrl" -ForegroundColor Cyan

if ($OpenInBrowser) {
    Start-Process $issueUrl
}
