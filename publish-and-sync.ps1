# C:\repos\Tools\publish-and-sync.ps1
# Full issue publishing workflow in one command:
#   1. Show open GitHub issues for the target repo (duplicate check)
#   2. Publish the local issue file to GitHub via publish-issue.ps1
#   3. Sync notes (commits the updated file with published_url to tools repo)
#
# Usage:
#   .\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md
#   .\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md -OpenInBrowser
#   .\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md -SkipDuplicateCheck
#   .\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md -CreatePR

param(
    [Parameter(Mandatory)][string]$File,
    [switch]$OpenInBrowser,
    [switch]$SkipDuplicateCheck,
    [switch]$CreatePR
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

# Parse repo from frontmatter using the shared parser
$parsed = Get-Frontmatter $File
$repo   = $parsed.Frontmatter['repo']

Write-Host ""
Write-Host "PUBLISH ISSUE  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray

# ── Step 1: Duplicate check ───────────────────────────────────────────────────
if ($SkipDuplicateCheck) {
    Write-Host ""
    Write-Host "Step 1 of 3 — Duplicate check (skipped)" -ForegroundColor DarkGray
} elseif ($repo) {
    Write-Host ""
    Write-Host "Step 1 of 3 — Open issues in wkcollis1-eng/$repo" -ForegroundColor White
    & "$PSScriptRoot\list-issues.ps1" -Remote -Repo $repo
    Write-Host ""
    # FIX: original prompt said "No duplicates found? Continue?" — phrasing assumed
    # no duplicates existed, confusing users who actually found one.
    $confirm = Read-Host "Review the open issues above. Publish anyway? (Y/n)"
    if ($confirm -match '^[Nn]$') {
        Write-Host "Publish cancelled." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host ""
    Write-Host "Step 1 of 3 — Duplicate check skipped (no repo in frontmatter)" -ForegroundColor Yellow
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

# Guard: check Tools repo working tree for unrelated staged changes that would
# be committed alongside the issue file.
$toolsPath   = $RepoMap["Tools"].Path
$uncommitted = git -C $toolsPath status --porcelain 2>$null |
               Where-Object { $_ -notmatch '^\s*[?][?]' -and $_ -notmatch 'issues[\\/]' }

if ($uncommitted) {
    Write-Host "Warning: Tools repo has unrelated staged/modified files:" -ForegroundColor Yellow
    $uncommitted | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Write-Host "  These would be committed alongside the issue file." -ForegroundColor Yellow
    $confirm = Read-Host "  Continue anyway? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Sync cancelled. Issue was published but local file not committed." -ForegroundColor Yellow
        Write-Host "Commit or stash your changes first, then run: .\sync-notes.ps1" -ForegroundColor Yellow
        exit 1
    }
}

$slug = Split-Path $File -Leaf
& "$PSScriptRoot\sync-notes.ps1" -Message "docs: publish issue $slug"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Sync failed — issue was published but local file not committed." -ForegroundColor Yellow
    Write-Host "Run: .\sync-notes.ps1 manually to save the published_url." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-Host "Done — issue published and local file synced." -ForegroundColor Green

# ── Step 4: Create PR (optional) ──────────────────────────────────────────────
if ($CreatePR) {
    Write-Host ""
    Write-Host "Step 4 — Create Pull Request" -ForegroundColor White

    $currentBranch = (git -C $toolsPath rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if ($currentBranch -eq "main") {
        $branchName = "publish-issue-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        git -C $toolsPath checkout -b $branchName 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Failed to create feature branch — PR skipped." -ForegroundColor Yellow
            exit 0
        }
        Write-Host "  Created branch: $branchName" -ForegroundColor Green
        $currentBranch = $branchName
    }

    git -C $toolsPath push --set-upstream origin $currentBranch 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to push branch — PR skipped." -ForegroundColor Yellow
        exit 0
    }

    $prTitle = "docs: publish issue $slug"
    $prBody  = "Publishes issue file with updated published_url.`n`nFile: $slug"
    $prUrl   = & gh pr create --title $prTitle --body $prBody --repo "wkcollis1-eng/Tools" 2>$null
    if ($LASTEXITCODE -eq 0 -and $prUrl) {
        Write-Host "  Pull Request created: $prUrl" -ForegroundColor Green
        if ($OpenInBrowser) { Start-Process $prUrl }
    } else {
        Write-Host "  PR creation failed — create manually:" -ForegroundColor Yellow
        Write-Host "    gh pr create --title `"$prTitle`" --repo wkcollis1-eng/Tools" -ForegroundColor Gray
    }
}
