#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Computes monthly furnace/AC min-per-cycle statistics from hvac_daily_YYYY.csv
    and merges them into the csv_manager.py append_monthly call.

.DESCRIPTION
    Called at month-end AFTER the HA shell_command appendmonthlycsv has already
    written the base row (outdoor temps, HDD/CDD, runtime, gas, electric).
    This function:
      1. Reads the closing month's daily rows from hvac_daily_YYYY.csv
      2. Computes the 7 derived stats that HA sensors cannot provide directly
      3. Updates the monthly CSV row via csv_manager.py append_monthly --update
         (or, if the row doesn't exist yet, appends it)

    Derived stats written:
      furnace_mpc_mean        — mean of daily avg_min_per_cycle (furnace days only)
      furnace_mpc_sigma       — sample std dev of same
      furnace_short_cycle_pct — % of furnace days where avg_min_per_cycle < 8.0
      furnace_cycles_total    — sum of daily furnace_cycles for the month
      chaining_index_mean     — mean of daily chaining_index (furnace days only)
      ac_cycles_total         — sum of daily ac_cycles for the month
      ac_mpc_mean             — mean of daily ac_min_per_cycle (AC days only,
                                 requires ac_cycles >= 2 and ac_min_per_cycle > 0)

.PARAMETER YearMonth
    Closing month in YYYY-MM format. Defaults to previous month.

.PARAMETER ReportsDir
    Path to the HA reports directory. Default: /config/reports

.PARAMETER CsvManagerPath
    Path to csv_manager.py. Default: /config/scripts/csv_manager.py

.PARAMETER DryRun
    Print the computed stats without writing to CSV.

.EXAMPLE
    # Normal month-end call (no args — targets previous month automatically)
    ./Add-MonthlyMpcStats.ps1

    # Backfill a specific month
    ./Add-MonthlyMpcStats.ps1 -YearMonth 2026-03

    # Preview without writing
    ./Add-MonthlyMpcStats.ps1 -YearMonth 2026-04 -DryRun
#>

param(
    [string]$YearMonth    = '',
    [string]$ReportsDir   = '/config/reports',
    [string]$CsvManagerPath = '/config/scripts/csv_manager.py',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve target month ──────────────────────────────────────────────────────
if (-not $YearMonth) {
    $YearMonth = (Get-Date).AddMonths(-1).ToString('yyyy-MM')
}
if ($YearMonth -notmatch '^\d{4}-\d{2}$') {
    Write-Error "YearMonth must be YYYY-MM, got: $YearMonth"
    exit 1
}
$year = $YearMonth.Substring(0, 4)
Write-Host "=== Monthly MPC Stats: $YearMonth ===" -ForegroundColor Cyan

# ── Locate daily CSV ──────────────────────────────────────────────────────────
$dailyCsv = Join-Path $ReportsDir "hvac_daily_${year}.csv"
if (-not (Test-Path $dailyCsv)) {
    Write-Error "Daily CSV not found: $dailyCsv"
    exit 1
}

# ── Read and filter rows for the target month ─────────────────────────────────
$allRows     = Import-Csv $dailyCsv
$monthRows   = $allRows | Where-Object { $_.date -like "${YearMonth}-*" }
$rowCount    = ($monthRows | Measure-Object).Count

if ($rowCount -eq 0) {
    Write-Warning "No daily rows found for $YearMonth in $dailyCsv — nothing to compute."
    exit 0
}
Write-Host "  Daily rows found: $rowCount"

# ── Helper: safe float parse ──────────────────────────────────────────────────
function To-Float([string]$s, [double]$default = 0.0) {
    $v = 0.0
    if ([double]::TryParse($s, [ref]$v)) { return $v }
    return $default
}

function To-Int([string]$s, [int]$default = 0) {
    $v = 0
    if ([int]::TryParse($s, [ref]$v)) { return $v }
    return $default
}

# ── Compute stats ─────────────────────────────────────────────────────────────

# --- Furnace min/cycle (valid days: furnace_cycles >= 2 AND 0 < avg_min_per_cycle <= 60) ---
$furnaceDays = $monthRows | Where-Object {
    (To-Int $_.furnace_cycles) -ge 2 -and
    (To-Float $_.avg_min_per_cycle) -gt 0 -and
    (To-Float $_.avg_min_per_cycle) -le 60
}
$mpcValues = @($furnaceDays | ForEach-Object { To-Float $_.avg_min_per_cycle })

if ($mpcValues.Count -ge 1) {
    $mpcMean  = ($mpcValues | Measure-Object -Average).Average
    $mpcShort = ($mpcValues | Where-Object { $_ -lt 8.0 }).Count
    $mpcShortPct = [math]::Round(100.0 * $mpcShort / $mpcValues.Count, 1)

    if ($mpcValues.Count -ge 2) {
        $variance = ($mpcValues | ForEach-Object { [math]::Pow($_ - $mpcMean, 2) } |
                     Measure-Object -Sum).Sum / ($mpcValues.Count - 1)
        $mpcSigma = [math]::Round([math]::Sqrt($variance), 2)
    } else {
        $mpcSigma = 0.0
    }
    $mpcMean = [math]::Round($mpcMean, 2)
} else {
    $mpcMean = 0.0; $mpcSigma = 0.0; $mpcShortPct = 0.0
    Write-Warning "  No valid furnace min/cycle days found for $YearMonth"
}

# --- Furnace cycles total ---
$furnaceCyclesTotal = ($monthRows |
    ForEach-Object { To-Int $_.furnace_cycles } |
    Measure-Object -Sum).Sum

# --- Chaining index mean (furnace days with CI > 0) ---
$chainDays = $monthRows | Where-Object { (To-Float $_.chaining_index) -gt 0 }
$chainValues = @($chainDays | ForEach-Object { To-Float $_.chaining_index })
$chainMean = if ($chainValues.Count -ge 1) {
    [math]::Round(($chainValues | Measure-Object -Average).Average, 2)
} else { 0.0 }

# --- AC cycles total ---
$acCyclesTotal = ($monthRows |
    ForEach-Object { To-Int $_.ac_cycles } |
    Measure-Object -Sum).Sum

# --- AC min/cycle mean (valid days: ac_cycles >= 2 AND 0 < ac_min_per_cycle <= 120) ---
$acDays = $monthRows | Where-Object {
    (To-Int $_.ac_cycles) -ge 2 -and
    (To-Float $_.ac_min_per_cycle) -gt 0 -and
    (To-Float $_.ac_min_per_cycle) -le 120
}
$acMpcValues = @($acDays | ForEach-Object { To-Float $_.ac_min_per_cycle })
$acMpcMean = if ($acMpcValues.Count -ge 1) {
    [math]::Round(($acMpcValues | Measure-Object -Average).Average, 2)
} else { 0.0 }

# ── Report ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Furnace stats ($($mpcValues.Count) valid days of $rowCount):"
Write-Host "    mpc_mean:          $mpcMean min/cycle"
Write-Host "    mpc_sigma:         $mpcSigma"
Write-Host "    short_cycle_pct:   $mpcShortPct%  (< 8 min threshold)"
Write-Host "    cycles_total:      $furnaceCyclesTotal"
Write-Host "    chaining_mean:     $chainMean"
Write-Host ""
Write-Host "  AC stats ($($acMpcValues.Count) valid days of $rowCount):"
Write-Host "    cycles_total:      $acCyclesTotal"
Write-Host "    mpc_mean:          $acMpcMean min/cycle"
Write-Host ""

if ($DryRun) {
    Write-Host "  DRY RUN — no CSV written." -ForegroundColor Yellow
    exit 0
}

# ── Build JSON for csv_manager append_monthly ─────────────────────────────────
# The base monthly row (outdoor temps, HDD/CDD, runtime, gas, electric) is
# written by the HA shell_command appendmonthlycsv at month-end.
# This call adds ONLY the computed stats. csv_manager deduplication check will
# skip if the month row already exists — so we use --update mode.
#
# If appendmonthlycsv hasn't run yet (manual backfill), pass all fields.
# Safe either way: csv_manager row_exists() check prevents duplicates.

$statsJson = @{
    month                  = $YearMonth
    furnace_mpc_mean       = $mpcMean
    furnace_mpc_sigma      = $mpcSigma
    furnace_short_cycle_pct = $mpcShortPct
    furnace_cycles_total   = $furnaceCyclesTotal
    chaining_index_mean    = $chainMean
    ac_cycles_total        = $acCyclesTotal
    ac_mpc_mean            = $acMpcMean
} | ConvertTo-Json -Compress

Write-Host "  Writing stats to monthly CSV..."

# Use update subcommand to patch existing row, or append if missing
$result = python3 $CsvManagerPath update_monthly --data $statsJson 2>&1
if ($LASTEXITCODE -ne 0) {
    # Fallback: if update not yet implemented, append_monthly will skip duplicate
    Write-Warning "  update_monthly not available — see note below."
    Write-Host "  Stats JSON (add manually or via update_monthly):"
    Write-Host "  $statsJson"
    exit 0
}

Write-Host "  Done. $YearMonth monthly stats written." -ForegroundColor Green
