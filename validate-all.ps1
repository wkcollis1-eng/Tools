# C:\repos\Tools\validate-all.ps1
# Runs validate_month.py against the Residential-HVAC-Performance-Baseline- repo.
# Validates all months by default, or a specific month with -Month.
# Exits 1 if any HALT-level check fails — safe to use as a pre-commit gate.
#
# Usage:
#   .\validate-all.ps1                       # validate all months in history
#   .\validate-all.ps1 -Month 2026-03        # validate March 2026 only
#   .\validate-all.ps1 -Month 2026-03-01     # same (YYYY-MM-01 format also accepted)
#   .\validate-all.ps1 -Json                 # also export results to validate-results.json

param(
    [string]$Month = "",
    [switch]$Json
)

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequirePython

. "$PSScriptRoot\repos.ps1"
$repoPath   = $RepoMap["Residential-HVAC-Performance-Baseline-"].Path
$scriptPath = "$repoPath\Scripts\validate_month.py"

if (-not (Test-Path $scriptPath)) {
    Write-Host "validate_month.py not found at: $scriptPath" -ForegroundColor Red
    Write-Host "Pull the repo first: .\pull-all-repos.ps1" -ForegroundColor Yellow
    exit 1
}

# Normalize month arg: accept YYYY-MM or YYYY-MM-DD, pass as YYYY-MM-01 to script
$monthArg = ""
if ($Month -ne "") {
    if ($Month -match '^\d{4}-\d{2}$') {
        $monthArg = "$Month-01"
    } elseif ($Month -match '^\d{4}-\d{2}-\d{2}$') {
        $monthArg = $Month
    } else {
        Write-Host "Invalid month format '$Month'. Use YYYY-MM or YYYY-MM-01." -ForegroundColor Red
        exit 1
    }
}

$exitCode = 0

# BUG FIX: Wrap Set-Location + python call in try/finally so the working directory
# is always restored even if Python throws an uncaught exception.
try {
    Set-Location $repoPath

    Write-Host ""
    if ($monthArg -ne "") {
        Write-Host "Running validation for $monthArg..." -ForegroundColor Green
        python Scripts\validate_month.py $monthArg
    } else {
        Write-Host "Running validation for all months..." -ForegroundColor Green
        python Scripts\validate_month.py
    }

    $exitCode = $LASTEXITCODE
} catch {
    Write-Host "Unexpected error during validation: $_" -ForegroundColor Red
    $exitCode = 1
} finally {
    # Always restore working directory — even on Python crash or Ctrl-C
    Set-Location $PSScriptRoot
}

Write-Host ""

if ($exitCode -ne 0) {
    Write-Host "HALT-level failures detected. Resolve before committing." -ForegroundColor Red
} else {
    Write-Host "Validation complete." -ForegroundColor Cyan
}

# ── Optional JSON export ───────────────────────────────────────────────────────
if ($Json) {
    $jsonOut = [PSCustomObject]@{
        Timestamp = (Get-Date -Format 'o')
        Repo      = "Residential-HVAC-Performance-Baseline-"
        Month     = if ($monthArg) { $monthArg } else { "all" }
        ExitCode  = $exitCode
        Passed    = ($exitCode -eq 0)
    }
    $outPath = "$PSScriptRoot\validate-results.json"
    $jsonOut | ConvertTo-Json | Set-Content $outPath -Encoding UTF8
    Write-Host "Results exported to: $outPath" -ForegroundColor DarkGray
}

exit $exitCode
