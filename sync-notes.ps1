# C:\repos\Tools\sync-notes.ps1
# Stages, commits, and pushes README and issue draft changes in the Tools repo.
# Use for README updates, issue drafts, and other documentation changes.
# Does nothing if there is nothing to commit in the scoped paths.
#
# Usage:
#   .\sync-notes.ps1
#   .\sync-notes.ps1 -Message "docs: add cooling buildout issue draft"

param(
    [string]$Message = ""
)

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "git is not installed or not on PATH." -ForegroundColor Red
    exit 1
}

Set-Location $PSScriptRoot

# Check overall working tree first for informational output
$allChanges = git status --porcelain
if (!$allChanges) {
    Write-Host "Nothing to sync — working tree is clean." -ForegroundColor Gray
    exit 0
}

# Scope git add to README.md and issues\ only — avoid staging .ps1 scripts or
# other code changes that belong in a proper code commit.
git add README.md 2>$null
if (Test-Path "$PSScriptRoot\issues") {
    git add issues\ 2>$null
}

# Check if anything was actually staged in those scoped paths
$staged = git diff --cached --name-only
if (!$staged) {
    Write-Host "No README or issues changes to sync." -ForegroundColor Gray
    Write-Host "(Other changes exist — commit them with a proper code commit message.)" -ForegroundColor DarkGray
    exit 0
}

Write-Host "Changes to sync:" -ForegroundColor Cyan
$staged | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

# Auto-generate commit message from staged files if none provided
if ($Message -eq "") {
    $issueFiles   = $staged | Where-Object { $_ -match '^issues[\\/]' }
    $readmeChange = $staged | Where-Object { $_ -match 'README\.md' }

    if ($issueFiles -and $readmeChange) {
        $Message = "docs: update README and $($issueFiles.Count) issue draft(s)"
    } elseif ($issueFiles) {
        $firstIssue = Split-Path ($issueFiles | Select-Object -First 1) -Leaf
        $Message = "docs: update issue draft ($firstIssue)"
    } else {
        $Message = "docs: update README"
    }
}

git commit -m $Message
if ($LASTEXITCODE -ne 0) {
    Write-Host "git commit failed." -ForegroundColor Red
    exit 1
}

git push
if ($LASTEXITCODE -ne 0) {
    # BUG FIX: Replace throw with Write-Host + exit 1 so parent scripts (session-end.ps1)
    # receive a clean exit code rather than a noisy terminating exception.
    Write-Host "git push failed. Check credentials (gh auth login)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Synced: $Message" -ForegroundColor Green
