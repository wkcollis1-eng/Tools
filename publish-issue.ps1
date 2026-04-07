# C:\repos\Tools\publish-issue.ps1
# Reads repo, title, and labels from a local issue file's YAML frontmatter
# and creates the GitHub issue via gh CLI.
# After a successful publish, writes published_url back into the frontmatter
# as a bidirectional audit record.
#
# Usage:
#   .\publish-issue.ps1 issues\ha-config_cooling-buildout.md
#   .\publish-issue.ps1 issues\ha-config_cooling-buildout.md -OpenInBrowser

param(
    [Parameter(Mandatory)][string]$File,
    [string[]]$Labels    = @(),
    [string[]]$Assignees = @(),
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
# Uses Get-Frontmatter from common.ps1 — single authoritative parser for all
# scripts that read issue files.
$parsed        = Get-Frontmatter $File
$frontmatter   = $parsed.Frontmatter
$bodyStartLine = $parsed.BodyStartLine
$lines         = $parsed.Lines

# ── Already published? ─────────────────────────────────────────────────────────
if ($frontmatter['published_url']) {
    Write-Host "This issue has already been published: $($frontmatter['published_url'])" -ForegroundColor Yellow
    $confirm = Read-Host "Publish again anyway? (y/N)"
    if ($confirm -notmatch '^[Yy]$') { exit 0 }
}

# ── Validate required fields ───────────────────────────────────────────────────
$repo   = $frontmatter['repo']
$title  = $frontmatter['title']
$fmLabels = $frontmatter['labels']

if (!$repo -or !$title) {
    Write-Host "Frontmatter missing 'repo' or 'title' in: $File" -ForegroundColor Red
    Write-Host "Expected format:" -ForegroundColor Yellow
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

# ── Extract body ───────────────────────────────────────────────────────────────
$body = ($lines[$bodyStartLine..($lines.Count - 1)] | Out-String).Trim()

if (!$body -or $body -match '<!--') {
    Write-Host "Issue body appears to still contain template placeholders." -ForegroundColor Yellow
    $confirm = Read-Host "Publish anyway? (y/N)"
    if ($confirm -notmatch '^[Yy]$') { exit 0 }
}

# ── Combine labels: frontmatter + command-line ─────────────────────────────────
$allLabels = @()
if ($fmLabels) {
    $allLabels += $fmLabels -split '[,;]\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
$allLabels += $Labels | Where-Object { $_ }

# ── Build and run gh command ───────────────────────────────────────────────────
# Body written to temp file to avoid Windows escaping issues with special chars.
$bodyFile = [System.IO.Path]::GetTempFileName()
try {
    Set-Content $bodyFile $body -Encoding UTF8

    $ghArgs = @(
        "issue", "create",
        "--repo",      "wkcollis1-eng/$repo",
        "--title",     $title,
        "--body-file", $bodyFile
    )
    foreach ($label in $allLabels) {
        # Only add labels that exist on the remote to avoid gh CLI crashes
        $exists = (gh label list --repo "wkcollis1-eng/$repo" | Select-String -Pattern "^$label\s" -SimpleMatch)
        if ($exists) {
            $ghArgs += @("--label", $label)
        } else {
            Write-Host "  Warning: Label '$label' not found on remote. Skipping." -ForegroundColor Yellow
        }
    }
    foreach ($a     in $Assignees)  { $ghArgs += @("--assignee", $a)     }

    Write-Host "Publishing issue to wkcollis1-eng/$repo..." -ForegroundColor Green
    Write-Host "  Title : $title" -ForegroundColor Cyan
    if ($allLabels) { Write-Host "  Labels: $($allLabels -join ', ')" -ForegroundColor Cyan }

    $issueUrl = & gh @ghArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "gh issue create failed." -ForegroundColor Red
        exit 1
    }
} finally {
    Remove-Item $bodyFile -ErrorAction SilentlyContinue
}

# Isolate URL from any warning lines gh may emit alongside it
$issueUrl = $issueUrl | Where-Object { $_ -match '^https://' } | Select-Object -First 1
Write-Host "Created: $issueUrl" -ForegroundColor Green

# ── Write published_url back to frontmatter ────────────────────────────────────
# FIX: original regex used bare `n (LF) which failed on CRLF files written on
# Windows — Get-Content returns CRLF line endings on Windows. Changed to `r?`n
# to match both CRLF and LF so the write-back works regardless of line endings.
$fileContent = Get-Content $File -Raw -Encoding UTF8
$fileContent = $fileContent -replace '(^---\r?`n(?:.*\r?`n)*?)---', "`$1published_url: $issueUrl`r`n---"
# FIX: removed -NoNewline — causes pre-commit end-of-file-fixer to flag every commit
Set-Content $File $fileContent -Encoding UTF8
Write-Host "Updated $File with published_url" -ForegroundColor DarkGray

if ($OpenInBrowser -and $issueUrl) {
    Start-Process $issueUrl
}
