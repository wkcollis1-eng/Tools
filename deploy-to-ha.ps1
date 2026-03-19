# C:\repos\tools\deploy-to-ha.ps1
# Copies live Python scripts to the HA Green Samba share.
# Run after any commit that modifies a script file in home-assistant-config\scripts\.
#
# Three scripts are deployed — all are called by shell commands in configuration.yaml:
#   climate_norms_today.py  — shell_command: climate_norms_today
#   csv_manager.py          — appenddailycsv, appendmonthlycsv, rotatedailycsv, backup_input_numbers
#   setback_csv.py          — appendsetbacklog_1f, appendsetbacklog_2f
#
# After running: Developer Tools → YAML → Reload Shell Commands

$deployMap = @{
    "C:\repos\home-assistant-config\scripts\climate_norms_today.py" = "\\homeassistant\config\scripts\climate_norms_today.py"
    "C:\repos\home-assistant-config\scripts\csv_manager.py"         = "\\homeassistant\config\scripts\csv_manager.py"
    "C:\repos\home-assistant-config\scripts\setback_csv.py"         = "\\homeassistant\config\scripts\setback_csv.py"
    # Add new scripts here — no other changes needed
}

# ── Pre-flight: verify all source files exist before touching the share ────────
$missingFiles = $deployMap.Keys | Where-Object { !(Test-Path $_) }
if ($missingFiles) {
    Write-Host "ABORTED — missing source file(s):" -ForegroundColor Red
    $missingFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host "Pull the repo first: .\pull-all-repos.ps1" -ForegroundColor Yellow
    exit 1
}

# ── Pre-flight: verify Samba share is reachable ────────────────────────────────
$shareRoot = "\\homeassistant\config\scripts"
if (!(Test-Path $shareRoot)) {
    Write-Host "ABORTED — Samba share not accessible: $shareRoot" -ForegroundColor Red
    Write-Host "Open File Explorer and connect to \\homeassistant\config before retrying." -ForegroundColor Yellow
    exit 1
}

# ── Deploy with hash verification ─────────────────────────────────────────────
$deployed = 0
$failed   = 0

foreach ($src in $deployMap.Keys) {
    $dst  = $deployMap[$src]
    $name = Split-Path $src -Leaf

    Copy-Item $src $dst -Force
    if ($LASTEXITCODE -ne 0 -and -not (Test-Path $dst)) {
        Write-Host "  FAILED to copy: $name" -ForegroundColor Red
        $failed++
        continue
    }

    # Hash verification — catches partial writes over Samba
    $srcHash = (Get-FileHash $src  -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash $dst  -Algorithm SHA256).Hash

    if ($srcHash -ne $dstHash) {
        Write-Host "  HASH MISMATCH after copy: $name" -ForegroundColor Red
        Write-Host "    src: $srcHash" -ForegroundColor Red
        Write-Host "    dst: $dstHash" -ForegroundColor Red
        $failed++
    } else {
        Write-Host "  Deployed: $name" -ForegroundColor Green
        $deployed++
    }
}

Write-Host ""
if ($failed -gt 0) {
    Write-Host "Deploy completed with $failed failure(s). DO NOT reload HA until resolved." -ForegroundColor Red
    exit 1
} else {
    Write-Host "$deployed script(s) deployed successfully." -ForegroundColor Cyan
    Write-Host "Next: Developer Tools → YAML → Reload Shell Commands" -ForegroundColor Yellow
}
