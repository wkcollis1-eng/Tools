# C:\repos\tools\publish-issue.ps1
# Reads repo, title, and labels from a local issue file's YAML frontmatter
# and creates the GitHub issue via gh CLI.
#
# Usage:
#   .\publish-issue.ps1 issues\ha-config_cooling-buildout.md
#   .\publish-issue.ps1 issues\ha-config_cooling-buildout.md -OpenInBrowser

param(
    [Parameter(Mandatory)][string]$File,
    [switch]$OpenInBrowser
)



. "$PSScriptRoot\common.ps1"
Assert-Environment -RequireGh

. "$PSScriptRoot\repos.ps1"

# Resolve relative path from tools root
if (![System.IO.Path]::IsPathRooted($File)) {
    $File = Join-Path $PSScriptRoot $File
}

if (!(Test-Path $File)) {
    Write-Host "File not found: $File" -ForegroundColor Red
    exit 1
}

# ── Parse YAML frontmatter ─────────────────────────────────────────────────────
# Frontmatter is between the first two --- lines
$raw   = Get-Content $File -Raw
$lines = Get-Content $File

$inFrontmatter = $false
$frontmatter   = @{}
$bodyStartLine = 0

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($i -eq 0 -and $line -eq '---') {
        $inFrontmatter = $true
        continue
    }
    if ($inFrontmatter -and $line -eq '---') {
        $bodyStartLine = $i + 1
        break
    }
    if ($inFrontmatter -and $line -match '^(\w+):\s*"?(.+?)"?\s*$') {
        $frontmatter[$Matches[1]] = $Matches[2]
    }
}

# ── Check if already published ────────────────────────────────────────────────
if ($frontmatter['published_url']) {
    Write-Host "This issue has already been published: $($frontmatter['published_url'])" -ForegroundColor Yellow
    $confirm = Read-Host "Publish again anyway? (y/N)"
    if ($confirm -notmatch '^[Yy]$') { exit 0 }
}

# ── Validate required fields ───────────────────────────────────────────────────
$repo   = $frontmatter['repo']
$title  = $frontmatter['title']
$labels = $frontmatter['labels']

if (!$repo -or !$title) {
    Write-Host "Frontmatter missing 'repo' or 'title' in: $File" -ForegroundColor Red
    Write-Host "Expected format at top of file:" -ForegroundColor Yellow
    Write-Host "  ---"
    Write-Host "  repo: home-assistant-config"
    Write-Host "  title: `"Your issue title`""
    Write-Host "  labels: enhancement"
    Write-Host "  ---"
    exit 1
}

if ($repo -notin $Repos) {
    Write-Host "Unknown repo '$repo' in frontmatter. Valid options:" -ForegroundColor Red
    $Repos | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# ── Extract body (everything after frontmatter) ────────────────────────────────
$body = ($lines[$bodyStartLine..($lines.Count - 1)] | Out-String).Trim()

if (!$body -or $body -match '<!--') {
    Write-Host "Issue body appears to still contain template placeholders." -ForegroundColor Yellow
    $confirm = Read-Host "Publish anyway? (y/N)"
    if ($confirm -notmatch '^[Yy]$') { exit 0 }
}

# ── Build gh command ───────────────────────────────────────────────────────────
# Write body to a temp file and use --body-file to avoid Windows argument
# escaping issues with backticks, code blocks, and special characters in --body.
$bodyFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content $bodyFile $body -Encoding UTF8

    $ghArgs = @(
        "issue", "create",
        "--repo",      "wkcollis1-eng/$repo",
        "--title",     $title,
        "--body-file", $bodyFile
    )

    if ($labels) {
        $ghArgs += @("--label", $labels)
    }

    Write-Host "Publishing issue to wkcollis1-eng/$repo..." -ForegroundColor Green
    Write-Host "  Title: $title" -ForegroundColor Cyan
    if ($labels) { Write-Host "  Labels: $labels" -ForegroundColor Cyan }

    $issueUrl = & gh @ghArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "gh issue create failed." -ForegroundColor Red
        exit 1
    }
} finally {
    Remove-Item $bodyFile -ErrorAction SilentlyContinue
}

Write-Host "Created: $issueUrl" -ForegroundColor Green

# ── Write published_url back to frontmatter ────────────────────────────────────
# Adds published_url to the frontmatter so the file serves as an audit record
$fileContent = Get-Content $File -Raw
$fileContent = $fileContent -replace "(^---`n(?:.*`n)*?)---", "`$1published_url: $issueUrl`n---"
Set-Content $File $fileContent -NoNewline
Write-Host "Updated $File with published_url" -ForegroundColor DarkGray

if ($OpenInBrowser) {
    Start-Process $issueUrl
}
