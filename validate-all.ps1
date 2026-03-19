# C:\repos\tools\validate-all.ps1
# Runs validate_month.py against the Residential-HVAC-Performance-Baseline- repo.
# Validates all months by default, or a specific month with -Month.
# Exits 1 if any HALT-level check fails — safe to use as a pre-commit gate.
#
# Usage:
#   .\validate-all.ps1                       # validate all months in history
#   .\validate-all.ps1 -Month 2026-03        # validate March 2026 only
#   .\validate-all.ps1 -Month 2026-03-01     # same (YYYY-MM-01 format also accepted)

param(
    [string]$Month = ""
)

if (!(Get-Command python -ErrorAction SilentlyContinue)) { throw "python is not installed or not on PATH." }

. "$PSScriptRoot\repos.ps1"
$repoPath  = "$ReposRoot\Residential-HVAC-Performance-Baseline-"
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

# Run from repo root so relative CSV paths in the script resolve correctly
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
Set-Location "$ReposRoot\tools"

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "HALT-level failures detected. Resolve before committing." -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "Validation complete." -ForegroundColor Cyan
    exit 0
}
