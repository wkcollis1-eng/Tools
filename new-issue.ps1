# C:\repos\Tools\new-issue.ps1
# Creates a new local issue file in Tools\issues\ from the standard template.
# Edit the file, then run publish-issue.ps1 to push it to GitHub.
#
# Usage:
#   .\new-issue.ps1 -Repo home-assistant-config -Slug "cooling-buildout"
#   .\new-issue.ps1 -Repo Residential-HVAC-Performance-Baseline- -Slug "march-2026-update"
#   .\new-issue.ps1 -Repo home-assistant-config -Slug "sensor-fix" -Open   # auto-open after create

param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Slug,
    [switch]$Open
)

. "$PSScriptRoot\repos.ps1"

if ($Repo -notin $Repos) {
    Write-Host "Unknown repo '$Repo'. Valid options:" -ForegroundColor Red
    $Repos | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# Sanitize slug — lowercase, hyphens only
$Slug = $Slug.ToLower() -replace '[^a-z0-9-]', '-' -replace '-+', '-'

# Derive a short repo prefix for the filename
$repoPrefix = switch ($Repo) {
    "home-assistant-config"                  { "ha-config" }
    "Residential-HVAC-Performance-Baseline-" { "hvac-baseline" }
    "Lifepo4-Battery-Banks"                  { "lifepo4" }
    "DIY-LiFePO4-UPS"                        { "ups" }
    "Tools"                                  { "tools" }   # BUG FIX: was "tools" (lowercase key)
    default                                  { $Repo.ToLower() -replace '[^a-z0-9]', '-' }
}

$issuesDir  = "$PSScriptRoot\issues"
$outputFile = "$issuesDir\${repoPrefix}_${Slug}.md"
$template   = "$issuesDir\TEMPLATE.md"

if (!(Test-Path $issuesDir)) {
    New-Item -Path $issuesDir -ItemType Directory | Out-Null
}

if (!(Test-Path $template)) {
    Write-Host "Template not found: $template" -ForegroundColor Red
    exit 1
}

if (Test-Path $outputFile) {
    Write-Host "File already exists: $outputFile" -ForegroundColor Yellow
    Write-Host "Delete it first or choose a different slug." -ForegroundColor Yellow
    exit 1
}

# Copy template and inject repo into frontmatter.
# Use a regex to match any existing 'repo: <value>' line so the replacement
# works regardless of what default repo the template contains.
$content = Get-Content $template -Raw
if ($content -match '(?m)^repo:\s*.+$') {
    $content = $content -replace '(?m)^repo:\s*.+$', "repo: $Repo"
} else {
    Write-Host "WARNING: template does not contain a 'repo:' frontmatter line — injecting one." -ForegroundColor Yellow
    $content = $content -replace '^---', "---`nrepo: $Repo"
}

# BUG FIX: Set-Content -NoNewline omits the trailing newline, which causes the
# pre-commit end-of-file-fixer hook to auto-correct it on every commit, creating
# a spurious diff. Write with a guaranteed trailing newline instead.
$content = $content.TrimEnd() + "`n"
Set-Content $outputFile $content -Encoding UTF8

Write-Host "Created: $outputFile" -ForegroundColor Green
Write-Host "Edit the file, then run:" -ForegroundColor Cyan
Write-Host "  .\publish-issue.ps1 issues\${repoPrefix}_${Slug}.md" -ForegroundColor Cyan

if ($Open) {
    # Enhancement: prefer VS Code if available, fall back to Notepad
    $vsCode = Get-Command code -ErrorAction SilentlyContinue
    if ($vsCode) {
        & code $outputFile
    } else {
        Start-Process notepad $outputFile
    }
}
