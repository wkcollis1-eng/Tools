# C:\repos\Tools\sync-notes.ps1
# Stages, commits, and pushes README.md and issues\ changes in the Tools repo.
# Deliberately scoped — only stages README.md and issues\, never .ps1 files or
# anything else (those belong in a proper code commit via push-all-repos.ps1).
# Does nothing if neither README.md nor issues\ has changes.
#
# Usage:
#   .\sync-notes.ps1                                            # auto-detect message
#   .\sync-notes.ps1 -Message "docs: add cooling buildout draft"

param(
    [string]$Message = ""
)

. "$PSScriptRoot\common.ps1"
Assert-Environment

Set-Location $PSScriptRoot

$changes = git status --porcelain 2>$null
if (!$changes) {
    Write-Host "Nothing to sync — working tree is clean." -ForegroundColor Gray
    exit 0
}

# ── Auto-detect commit message ────────────────────────────────────────────────
if (!$Message) {
    $fileList = @()
    foreach ($line in $changes) {
        $file = $line.Substring(3).Trim()
        if ($file -match '\.md$' -or $file -match '^issues[/\\]') {
            $fileList += $file
        }
    }

    if ($fileList.Count -eq 0) {
        $Message = "docs: update notes and issue files"
    } elseif ($fileList.Count -eq 1) {
        $file = $fileList[0]
        if ($file -eq 'README.md') {
            $Message = "docs: update README.md"
        } elseif ($file -match '^issues[/\\](.+)$') {
            $Message = "docs: update issues/$($Matches[1])"
        } else {
            $Message = "docs: update $file"
        }
    } else {
        $issueFiles = $fileList | Where-Object { $_ -match '^issues[/\\]' }
        $otherFiles = $fileList | Where-Object { $_ -notmatch '^issues[/\\]' }
        if ($issueFiles.Count -gt 0 -and $otherFiles.Count -eq 0) {
            $Message = if ($issueFiles.Count -eq 1) {
                "docs: update issues/$($issueFiles[0] -replace '^issues[/\\]', '')"
            } else { "docs: update multiple issue files" }
        } elseif ($issueFiles.Count -gt 0 -and $otherFiles.Count -gt 0) {
            $Message = "docs: update notes and issue files"
        } else {
            $Message = "docs: update notes"
        }
    }
}

Write-Host "Changes to sync:" -ForegroundColor Cyan
git status --short

# ── Stage only scoped paths ───────────────────────────────────────────────────
# Explicit scoping prevents accidentally staging .ps1 files or other changes
# that belong in a code commit rather than a doc sync.
if (Test-Path (Join-Path $PSScriptRoot "README.md")) { git add "README.md" }
if (Test-Path (Join-Path $PSScriptRoot "issues"))     { git add "issues/" }

$staged = git diff --cached --name-only 2>$null
if (!$staged) {
    Write-Host "Nothing staged after scoped add (no README.md or issues\ changes)." -ForegroundColor Gray
    exit 0
}

git commit -m $Message
if ($LASTEXITCODE -ne 0) {
    Write-Host "git commit failed." -ForegroundColor Red
    exit 1
}

# FIX: 'throw "git push failed..."' replaced with Write-Host + exit 1.
# throw unwinds differently from exit 1 when called from a parent script —
# the error display may be noisy or swallowed depending on the caller's
# error handling. exit 1 is the toolkit standard for hard failures.
git push
if ($LASTEXITCODE -ne 0) {
    Write-Host "git push failed — check credentials (gh auth login)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Synced: $Message" -ForegroundColor Green
