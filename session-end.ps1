# C:\repos\Tools\session-end.ps1
# Single entry point for ending any work session.
# Runs the full post-session sequence: status check, optional deploy, push, sync.
#
# Usage:
#   .\session-end.ps1              # prompts whether to deploy
#   .\session-end.ps1 -Deploy      # always deploy (skip prompt)
#   .\session-end.ps1 -NoDeploy    # skip deploy entirely
#   .\session-end.ps1 -NoSync      # skip sync-notes (e.g. no doc changes)

param(
    [switch]$Deploy,
    [switch]$NoDeploy,
    [switch]$NoSync
)

. "$PSScriptRoot\common.ps1"
Assert-Environment
. "$PSScriptRoot\repos.ps1"

Write-Host ""
Write-Host "SESSION END  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray

# ── Step 1: Status — show what changed this session ───────────────────────────
Write-Host ""
Write-Host "Step 1 of 4 — Repo status" -ForegroundColor White
& "$PSScriptRoot\status-all-repos.ps1"

# ── Step 2: Deploy to HA (conditional) ────────────────────────────────────────
Write-Host ""
Write-Host "Step 2 of 4 — Deploy to HA Green" -ForegroundColor White

$shouldDeploy = $false

if ($Deploy) {
    $shouldDeploy = $true
} elseif ($NoDeploy) {
    Write-Host "  Skipped (-NoDeploy)" -ForegroundColor Gray
} else {
    $haPath = $RepoMap["home-assistant-config"].Path
    $pyChanged   = $false
    $yamlChanged = $false

    if (Test-Path "$haPath\.git") {
        Set-Location $haPath

        # BUG FIX 1: Guard against first-commit repos that have no HEAD~1.
        # BUG FIX 2: Use @{u}..HEAD (all unpushed commits) instead of HEAD~1..HEAD
        #            (only the last commit) so multi-commit sessions are covered.
        $commitCount = [int](git rev-list --count HEAD 2>$null)
        $hasUpstream = (git rev-parse --abbrev-ref "@{u}" 2>$null) -and ($LASTEXITCODE -eq 0)

        $diffRange = if ($hasUpstream) {
            "@{u}..HEAD"
        } elseif ($commitCount -gt 1) {
            "HEAD~1..HEAD"
        } else {
            $null   # Single commit, no upstream — skip diff
        }

        if ($diffRange) {
            $changedFiles = git diff --name-only $diffRange 2>$null
            $pyChanged    = $changedFiles -match '\.py$'
            $yamlChanged  = $changedFiles -match '\.(yaml|yml)$'
        }

        Set-Location $PSScriptRoot
    }

    # Remind about YAML domain reloads before prompting for deploy
    if ($yamlChanged) {
        Write-Host ""
        Write-Host "  ⚠  YAML changes detected in home-assistant-config." -ForegroundColor Yellow
        Write-Host "     Remember to reload the affected HA domain after deploy" -ForegroundColor Yellow
        Write-Host "     (Developer Tools → YAML → Reload [domain])." -ForegroundColor DarkGray
        Write-Host ""
    }

    if ($pyChanged) {
        Write-Host "  Python script change detected in home-assistant-config." -ForegroundColor Yellow
        $answer = Read-Host "  Deploy to HA Green? (Y/n)"
        $shouldDeploy = $answer -notmatch '^[Nn]$'
    } else {
        $answer = Read-Host "  Deploy to HA Green? (y/N)"
        $shouldDeploy = $answer -match '^[Yy]$'
    }
}

if ($shouldDeploy) {
    & "$PSScriptRoot\deploy-to-ha.ps1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Deploy failed — resolve before pushing. Session end ABORTED." -ForegroundColor Red
        exit 1
    }
}

# ── Step 3: Push all repos ────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 3 of 4 — Push all repos" -ForegroundColor White
& "$PSScriptRoot\push-all-repos.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Push failed — check output above." -ForegroundColor Red
    exit 1
}

# ── Step 4: Sync notes (README, issue drafts) ─────────────────────────────────
Write-Host ""
Write-Host "Step 4 of 4 — Sync notes" -ForegroundColor White

if ($NoSync) {
    Write-Host "  Skipped (-NoSync)" -ForegroundColor Gray
} else {
    & "$PSScriptRoot\sync-notes.ps1"
}

Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-Host "Session complete." -ForegroundColor Green
