# C:\repos\Tools\publish-and-sync.ps1
# Full issue publishing workflow in one command:
#   1. List open GitHub issues for the target repo (duplicate check)
#   2. Publish the local issue file to GitHub
#   3. Sync notes (commits the updated file with published_url back to tools repo)
#
# Usage:
#   .\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md
#   .\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md -OpenInBrowser
#   .\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md -SkipDuplicateCheck

param(
    [Parameter(Mandatory)][string]$File,
    [switch]$OpenInBrowser,
    [switch]$SkipDuplicateCheck
)

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequireGh
. "$PSScriptRoot\repos.ps1"

# Resolve path
if (![System.IO.Path]::IsPathRooted($File)) {
    $File = Join-Path $PSScriptRoot $File
}

if (!(Test-Path $File)) {
    Write-Host "File not found: $File" -ForegroundColor Red
    exit 1
}

# Parse repo from frontmatter for the duplicate check
$lines = Get-Content $File
$repo  = ""
$inFM  = $false
foreach ($line in $lines) {
    $l = $line.Trim()
    if (!$inFM -and $l -eq '---') { $inFM = $true; continue }
    if ($inFM  -and $l -eq '---') { break }
    if ($inFM  -and $l -match '^repo:\s*(.+)$') { $repo = $Matches[1].Trim() }
}

Write-Host ""
Write-Host "PUBLISH ISSUE  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray

# ── Step 1: Duplicate check ───────────────────────────────────────────────────
if ($SkipDuplicateCheck) {
    Write-Host ""
    Write-Host "Step 1 of 3 — Duplicate check (skipped)" -ForegroundColor Gray
} elseif ($repo) {
    Write-Host ""
    Write-Host "Step 1 of 3 — Open issues in wkcollis1-eng/$repo" -ForegroundColor White
    & "$PSScriptRoot\list-issues.ps1" -Remote -Repo $repo
    Write-Host ""
    $confirm = Read-Host "No duplicates found? Continue to publish? (Y/n)"
    if ($confirm -match '^[Nn]$') {
        Write-Host "Publish cancelled." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host ""
    Write-Host "Step 1 of 3 — Duplicate check skipped (repo not found in frontmatter)" -ForegroundColor Yellow
}

# ── Step 2: Publish ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 2 of 3 — Publish to GitHub" -ForegroundColor White

$publishArgs = @($File)
if ($OpenInBrowser) { $publishArgs += "-OpenInBrowser" }

& "$PSScriptRoot\publish-issue.ps1" @publishArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Publish failed — sync skipped." -ForegroundColor Red
    exit 1
}

# ── Step 3: Sync notes ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 3 of 3 — Sync notes" -ForegroundColor White

$slug = Split-Path $File -Leaf
try {
    & "$PSScriptRoot\sync-notes.ps1" -Message "docs: publish issue $slug"
    if ($LASTEXITCODE -ne 0) { throw "sync-notes exited $LASTEXITCODE" }
} catch {
    Write-Host "Sync failed — issue was published but local file not committed." -ForegroundColor Yellow
    Write-Host "Run: .\sync-notes.ps1 manually to save the published_url." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-Host "Done — issue published and local file synced." -ForegroundColor Green
