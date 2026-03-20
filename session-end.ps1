# C:\repos\Tools\session-end.ps1
# Single entry point for ending any work session.
# Runs: status check → optional HA deploy → push all repos → sync notes.
#
# Usage:
#   .\session-end.ps1                # prompts whether to deploy
#   .\session-end.ps1 -Deploy        # always deploy (skip prompt)
#   .\session-end.ps1 -NoDeploy      # skip deploy entirely
#   .\session-end.ps1 -NoSync        # skip sync-notes (no doc changes)
#   .\session-end.ps1 -ForceDeploy   # alias for -Deploy (more self-documenting)
#   .\session-end.ps1 -ForceNoDeploy # alias for -NoDeploy

param(
    [switch]$Deploy,
    [switch]$NoDeploy,
    [switch]$NoSync,
    [switch]$ForceDeploy,
    [switch]$ForceNoDeploy
)

. "$PSScriptRoot\common.ps1"
Assert-Environment
. "$PSScriptRoot\repos.ps1"

Write-Host ""
Write-Host "SESSION END  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray

# ── Step 1: Status ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 1 of 4 — Repo status" -ForegroundColor White
& "$PSScriptRoot\status-all-repos.ps1"

# ── Step 2: Deploy to HA (conditional) ────────────────────────────────────────
Write-Host ""
Write-Host "Step 2 of 4 — Deploy to HA Green" -ForegroundColor White

$shouldDeploy = $false

if ($Deploy -or $ForceDeploy) {
    $shouldDeploy = $true
} elseif ($NoDeploy -or $ForceNoDeploy) {
    Write-Host "  Skipped (-NoDeploy)" -ForegroundColor DarkGray
} else {
    # Auto-detect .py and .yaml changes in home-assistant-config across all
    # unpushed commits (@{u}..HEAD), not just HEAD~1 — captures multi-commit sessions.
    # FIX: original used HEAD~1..HEAD which only looked at the last commit.
    $haPath       = $RepoMap["home-assistant-config"].Path
    $pyChanged    = $false
    $yamlChanged  = $false
    $changedDomains = @()

    if (Test-GitRepo $haPath) {
        # Check whether an upstream tracking branch exists before using @{u}
        $hasUpstream = git -C $haPath rev-parse --verify "@{u}" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $changedFiles = git -C $haPath diff --name-only "@{u}..HEAD" 2>$null
        } else {
            # No upstream yet — fall back to last commit only (first-push scenario)
            $commitCount = [int]((git -C $haPath rev-list --count HEAD 2>$null).Trim() -as [int])
            $changedFiles = if ($commitCount -gt 1) {
                git -C $haPath diff --name-only "HEAD~1..HEAD" 2>$null
            } else { @() }
        }

        $pyChanged   = $changedFiles -match '\.py$'
        $yamlChanged = $changedFiles -match '\.ya?ml$'

        # Identify which HA domains have YAML changes for the reload reminder
        if ($yamlChanged) {
            $domainPatterns = @{
                "automation"    = 'automation:'
                "script"        = 'script:'
                "switch"        = 'switch:'
                "sensor"        = 'sensor:'
                "binary_sensor" = 'binary_sensor:'
                "climate"       = 'climate:'
                "input_select"  = 'input_select:'
                "shell_command" = 'shell_command:'
            }
            foreach ($file in ($changedFiles | Where-Object { $_ -match '\.ya?ml$' })) {
                $fullPath = Join-Path $haPath $file
                if (Test-Path $fullPath) {
                    $content = Get-Content $fullPath -Raw -ErrorAction SilentlyContinue
                    foreach ($domain in $domainPatterns.Keys) {
                        if ($content -match $domainPatterns[$domain]) {
                            $changedDomains += $domain
                        }
                    }
                }
            }
            $changedDomains = $changedDomains | Sort-Object -Unique
        }
    }

    if ($pyChanged -or $yamlChanged) {
        if ($pyChanged) {
            Write-Host "  Python script change detected in home-assistant-config." -ForegroundColor Yellow
        }
        if ($yamlChanged) {
            Write-Host "  YAML change detected in home-assistant-config." -ForegroundColor Yellow
            if ($changedDomains.Count -gt 0) {
                Write-Host "  Affected domains: $($changedDomains -join ', ')" -ForegroundColor Gray
                Write-Host "  Remember to reload these domains in HA after deploy." -ForegroundColor Cyan
            }
        }
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
        Write-Host "Deploy failed — session end ABORTED. Resolve before pushing." -ForegroundColor Red
        exit 1
    }

    # Optional: HA persistent notification via REST API.
    # Set $env:HA_TOKEN to your long-lived HA token to enable this.
    if ($env:HA_TOKEN) {
        $haUrl   = "http://homeassistant.local:8123"
        $headers = @{ "Authorization" = "Bearer $env:HA_TOKEN"; "Content-Type" = "application/json" }
        $body    = @{ message = "Scripts deployed via session-end.ps1"; title = "Deployment Complete" } |
                       ConvertTo-Json
        try {
            Invoke-RestMethod -Uri "$haUrl/api/services/persistent_notification/create" `
                -Method Post -Headers $headers -Body $body -TimeoutSec 5 | Out-Null
            Write-Host "  HA notification sent." -ForegroundColor DarkGray
        } catch {
            Write-Host "  HA notification skipped (API unreachable)." -ForegroundColor DarkGray
        }
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

# ── Step 4: Sync notes ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 4 of 4 — Sync notes" -ForegroundColor White

if ($NoSync) {
    Write-Host "  Skipped (-NoSync)" -ForegroundColor DarkGray
} else {
    & "$PSScriptRoot\sync-notes.ps1"
}

Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-Host "Session complete." -ForegroundColor Green
