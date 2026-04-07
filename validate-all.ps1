# C:\repos\Tools\validate-all.ps1
# Runs validate_month.py against the Residential-HVAC-Performance-Baseline- repo.
# Validates all months by default, or a specific month with -Month.
# Exits 1 if any HALT-level check fails — safe to use as a pre-release gate.
#
# Usage:
#   .\validate-all.ps1                    # validate all months in history
#   .\validate-all.ps1 -Month 2026-03     # validate March 2026 only
#   .\validate-all.ps1 -Month 2026-03-01  # same (YYYY-MM-01 also accepted)
#   .\validate-all.ps1 -Json              # export JSON results to validate-results.json

param(
    [string]$Month    = "",
    [switch]$AllRepos,
    [switch]$Json
)

$env:PYTHONUTF8 = 1

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequirePython
. "$PSScriptRoot\repos.ps1"

# ── Month normalisation ───────────────────────────────────────────────────────
# FIX: $monthArg was computed AFTER the foreach loop that used it, so -Month was
# silently ignored and all-months validation always ran. Moved here, before the loop.
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

# ── Target repos ──────────────────────────────────────────────────────────────
$targetRepos = if ($AllRepos) { $Repos } else { @("Residential-HVAC-Performance-Baseline-") }

$validationResults = [System.Collections.Generic.List[hashtable]]::new()
$overallSuccess    = $true

foreach ($repo in $targetRepos) {
    # Currently only the HVAC repo has a validation script
    if ($repo -ne "Residential-HVAC-Performance-Baseline-") {
        Write-Host "[$repo] No validation script available — skipping" -ForegroundColor Yellow
        continue
    }

    $repoPath   = $RepoMap[$repo].Path
    $scriptPath = "$repoPath\Scripts\validate_month.py"

    if (-not (Test-Path $scriptPath)) {
        $msg = "validate_month.py not found at: $scriptPath`nPull the repo first: .\pull-all-repos.ps1"
        Write-Host $msg -ForegroundColor Red
        $validationResults.Add(@{ Repo = $repo; Success = $false; Error = $msg; Output = @() })
        $overallSuccess = $false
        continue
    }

    $label   = if ($monthArg) { $monthArg } else { "all months" }
    $message = "Running validation for $label in $repo..."
    Write-Host $message -ForegroundColor Green

    $scriptOutput = @()
    $exitCode     = 0

    # FIX: Set-Location is now inside try with finally — working directory is
    # always restored even if Python throws an uncaught exception.
    Push-Location $repoPath
    try {
        $pythonArgs = @("Scripts\validate_month.py")
        if ($monthArg) { $pythonArgs += $monthArg }

        $output   = python @pythonArgs 2>&1
        $exitCode = $LASTEXITCODE

        # Normalise output to a clean string array
        $scriptOutput = ($output -join "`n") -split "`n" | Where-Object { $_.Trim() -ne "" }

        # Print validation output to console in all modes
        $scriptOutput | ForEach-Object { Write-Host "  $_" }

    } catch {
        $scriptOutput += "Exception: $_"
        $exitCode = 1
    } finally {
        Pop-Location
    }

    $result = @{
        Repo     = $repo
        Success  = ($exitCode -eq 0)
        ExitCode = $exitCode
        Month    = $monthArg
        Output   = $scriptOutput
    }
    if ($exitCode -ne 0) {
        $overallSuccess = $false
        $result['Error'] = if ($scriptOutput.Count -gt 0) { $scriptOutput[-1] } else { "exit code $exitCode" }
    }
    $validationResults.Add($result)
}

# ── Output ────────────────────────────────────────────────────────────────────
if ($Json) {
    $jsonOutput = @{
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        Month     = $monthArg
        Success   = $overallSuccess
        Results   = $validationResults
    }
    $outFile = Join-Path $PSScriptRoot "validate-results.json"
    $jsonOutput | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8
    Write-Host ""
    Write-Host "JSON results written to: $outFile" -ForegroundColor DarkGray
}

Write-Host ""
if ($overallSuccess) {
    Write-Host "Validation complete." -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "HALT-level failures detected. Resolve before committing." -ForegroundColor Red
    exit 1
}
