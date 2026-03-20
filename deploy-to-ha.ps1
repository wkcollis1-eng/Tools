# C:\repos\Tools\deploy-to-ha.ps1
# Copies live Python scripts to the HA Green Samba share.
# Run after any commit that modifies a script file in home-assistant-config\scripts\.
#
# Three scripts are deployed — all are called by shell commands in configuration.yaml:
#   climate_norms_today.py  — shell_command: climate_norms_today
#   csv_manager.py          — appenddailycsv, appendmonthlycsv, rotatedailycsv, backup_input_numbers
#   setback_csv.py          — appendsetbacklog_1f, appendsetbacklog_2f
#
# After running: Developer Tools → YAML → Reload Shell Commands

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequireSamba      # verifies Samba share is reachable before proceeding

. "$PSScriptRoot\repos.ps1"

# ── Deploy map: source (local) → destination (Samba share) ────────────────────
# Uses $ReposRoot from repos.ps1 and $SambaSharePath from common.ps1 —
# no hardcoded paths so the map adapts to -ReposRoot overrides.
$deployMap = @{
    "$ReposRoot\home-assistant-config\scripts\climate_norms_today.py" = "$SambaSharePath\climate_norms_today.py"
    "$ReposRoot\home-assistant-config\scripts\csv_manager.py"         = "$SambaSharePath\csv_manager.py"
    "$ReposRoot\home-assistant-config\scripts\setback_csv.py"         = "$SambaSharePath\setback_csv.py"
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

# ── Helper: copy with 1 retry on Samba transient failures ─────────────────────
function Copy-WithRetry {
    param(
        [string]$Source,
        [string]$Destination,
        [int]$RetryDelaySec = 3
    )
    try {
        Copy-Item $Source $Destination -Force -ErrorAction Stop
        return $true
    } catch {
        $err1 = $_
        Write-Host "    Copy failed ($err1) — retrying in ${RetryDelaySec}s..." -ForegroundColor Yellow
        Start-Sleep -Seconds $RetryDelaySec
        try {
            Copy-Item $Source $Destination -Force -ErrorAction Stop
            return $true
        } catch {
            Write-Host "    FAILED after retry: $_" -ForegroundColor Red
            return $false
        }
    }
}

# ── Deploy with hash verification ─────────────────────────────────────────────
$deployed = 0
$failed   = 0

foreach ($src in $deployMap.Keys) {
    $dst  = $deployMap[$src]
    $name = Split-Path $src -Leaf

    Write-Host "  Deploying $name..." -ForegroundColor DarkGray
    $copyOk = Copy-WithRetry -Source $src -Destination $dst
    if (!$copyOk) {
        $failed++
        continue
    }

    # Hash verification — catches partial writes over Samba
    $srcHash = (Get-FileHash $src -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash $dst -Algorithm SHA256).Hash

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
}

# ── Write deploy record to HA share ───────────────────────────────────────────
# Always written on success so verify-system.ps1 can detect stale deployments.
$commitHash = git -C "$ReposRoot\home-assistant-config" rev-parse --short HEAD 2>$null
if (!$commitHash) { $commitHash = "unknown" }
$timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$version    = "$timestamp | $deployed script(s) | home-assistant-config@$commitHash"

try {
    Set-Content "$SambaSharePath\DEPLOY_VERSION.txt" $version -ErrorAction Stop
} catch {
    Write-Host "Warning: could not write DEPLOY_VERSION.txt — $_" -ForegroundColor Yellow
    Write-Host "Scripts deployed successfully but deploy record was not updated." -ForegroundColor Yellow
}

Write-Host "$deployed script(s) deployed and verified." -ForegroundColor Cyan
Write-Host "Deploy record: $version" -ForegroundColor DarkGray
Write-Host "Next: Developer Tools → YAML → Reload Shell Commands" -ForegroundColor Yellow
