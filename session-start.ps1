# C:\repos\Tools\session-start.ps1
# Single entry point for starting any work session.
# Runs the full pre-session sequence and stops on any hard failure.
#
# Usage:
#   .\session-start.ps1          # standard session start (verify + pull + status)
#   .\session-start.ps1 -NoPull  # offline work — skip network pull

param(
    [switch]$NoPull
)

. "$PSScriptRoot\common.ps1"
Assert-Environment
. "$PSScriptRoot\repos.ps1"

Write-Host ""
Write-Host "SESSION START  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray

# ── Step 1: Environment health check ─────────────────────────────────────────
Write-Host ""
Write-Host "Step 1 of 3 — Environment check" -ForegroundColor White
& "$PSScriptRoot\verify-system.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Session start ABORTED — resolve failures above before proceeding." -ForegroundColor Red
    exit 1
}

# ── Step 2: Pull all repos ────────────────────────────────────────────────────
Write-Host ""
if ($NoPull) {
    Write-Host "Step 2 of 3 — Pull all repos (skipped — -NoPull)" -ForegroundColor DarkGray
} else {
    Write-Host "Step 2 of 3 — Pull all repos" -ForegroundColor White
    & "$PSScriptRoot\pull-all-repos.ps1"
    # pull-all-repos exits 1 only on total failure (all repos failed).
    # Per-repo diverged/failed cases are soft and logged in its summary.
    # Check exit code for the all-repos-failed case only.
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Session start ABORTED — all repos failed to pull." -ForegroundColor Red
        Write-Host "Check network connectivity and gh auth status, then retry." -ForegroundColor Yellow
        exit 1
    }
}

# ── Step 3: Status overview ───────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 3 of 3 — Repo status" -ForegroundColor White
& "$PSScriptRoot\status-all-repos.ps1"

Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-Host "Session ready. Run .\session-end.ps1 when done." -ForegroundColor Green
