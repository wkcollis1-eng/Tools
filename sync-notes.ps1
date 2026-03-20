# C:\repos\tools\sync-notes.ps1
# Stages, commits, and pushes any text/doc changes in the tools repo.
# Use for README updates, issue drafts, and other non-code changes.
# Does nothing if there is nothing to commit.
#
# Usage:
#   .\sync-notes.ps1
#   .\sync-notes.ps1 -Message "docs: add cooling buildout issue draft"

param(
    [string]$Message = "docs: update notes and issue files"
)

if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed or not on PATH." }

Set-Location $PSScriptRoot

$changes = git status --porcelain
if (!$changes) {
    Write-Host "Nothing to sync — working tree is clean." -ForegroundColor Gray
    exit 0
}

Write-Host "Changes to sync:" -ForegroundColor Cyan
git status --short

# Stage only doc/issue files — not .ps1 scripts (those are code changes, not notes).
# Scope: markdown files, issues directory, and YAML/config docs at repo root.
git add "*.md" "issues" "*.yaml" "*.yml"
git commit -m $Message
if ($LASTEXITCODE -ne 0) { throw "git commit failed." }

git push
if ($LASTEXITCODE -ne 0) { throw "git push failed. Check credentials (gh auth login)." }

Write-Host ""
Write-Host "Synced: $Message" -ForegroundColor Green
