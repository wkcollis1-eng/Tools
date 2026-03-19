# C:\repos\Tools\session-start.ps1
# Single entry point for starting any work session.
# Runs the full pre-session sequence and stops on any hard failure.
#
# Usage:
#   .\session-start.ps1

. "$PSScriptRoot\common.ps1"
Assert-Environment
. "$PSScriptRoot\repos.ps1"

Write-Host ""
Write-Host "SESSION START  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray

# ── Step 1: Full environment health check ─────────────────────────────────────
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
Write-Host "Step 2 of 3 — Pull all repos" -ForegroundColor White
& "$PSScriptRoot\pull-all-repos.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Session start ABORTED — pull failed. Resolve conflicts before proceeding." -ForegroundColor Red
    exit 1
}

# ── Step 3: Status overview ───────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 3 of 3 — Repo status" -ForegroundColor White
& "$PSScriptRoot\status-all-repos.ps1"

Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-Host "Session ready. Run .\session-end.ps1 when done." -ForegroundColor Green
