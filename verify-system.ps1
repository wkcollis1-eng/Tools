# C:\repos\Tools\verify-system.ps1
# Full environment health check. Run at the start of any session to confirm
# the system is in a known-good state before doing real work.
#
# Checks:
#   - git, gh, python installed and configured
#   - All repos cloned, on main, working trees clean
#   - Repo divergence from origin/main detected
#   - Pre-commit hooks installed per repo
#   - HA Samba share reachable and writable
#   - Deployed scripts present on share
#
# Usage:
#   .\verify-system.ps1              # Standard health check
#   .\verify-system.ps1 -NoFetch    # Skip git fetch (faster, offline-safe)
#   .\verify-system.ps1 -Json       # Export results to verify-results.json

param(
    [switch]$NoFetch,
    [switch]$Json
)

. "$PSScriptRoot\common.ps1"
Assert-Environment      # Hard-stop if git/gh/python missing before detailed checks
. "$PSScriptRoot\repos.ps1"

$pass    = 0
$warn    = 0
$fail    = 0
$results = [System.Collections.Generic.List[object]]::new()

function Ok($msg) {
    Write-Host "  OK    $msg" -ForegroundColor Green
    $script:pass++
    $script:results.Add([PSCustomObject]@{ Level = "OK";   Message = $msg })
}
function Warn($msg) {
    Write-Host "  WARN  $msg" -ForegroundColor Yellow
    $script:warn++
    $script:results.Add([PSCustomObject]@{ Level = "WARN"; Message = $msg })
}
function Fail($msg) {
    Write-Host "  FAIL  $msg" -ForegroundColor Red
    $script:fail++
    $script:results.Add([PSCustomObject]@{ Level = "FAIL"; Message = $msg })
}

Write-Host ""
Write-Host "System Verification  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("─" * 50) -ForegroundColor DarkGray

# ── Tools ─────────────────────────────────────────────────────────────────────
# Assert-Environment above already hard-stops on missing tools.
# This section reports version detail and configuration quality.
Write-Host ""
Write-Host "TOOLS" -ForegroundColor White

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVersion = git --version 2>$null
    $gitName    = git config user.name  2>$null
    $gitEmail   = git config user.email 2>$null
    if ($gitName -and $gitEmail) {
        Ok "git — $gitVersion ($gitName <$gitEmail>)"
    } else {
        Fail "git installed but identity not configured (run: git config --global user.name / user.email)"
    }
} else {
    Fail "git not found — https://git-scm.com/download/win"
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $null = gh auth status 2>$null
    if ($LASTEXITCODE -eq 0) {
        $ghVersion = gh --version 2>$null | Select-Object -First 1
        Ok "gh  — $ghVersion"
    } else {
        Fail "gh installed but not authenticated (run: gh auth login)"
    }
} else {
    Fail "gh not found — https://cli.github.com"
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    $pyVersion = python --version 2>$null
    Ok "python — $pyVersion"
} else {
    Warn "python not found (required for validate-all, install-precommit-all, monthly-update)"
}

# ── Repos ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "REPOS" -ForegroundColor White

foreach ($repo in $Repos) {
    $path = $RepoMap[$repo].Path

    if (!(Test-Path "$path\.git")) {
        Fail "$repo — not cloned (run: .\clone-all-repos.ps1)"
        continue
    }

    Set-Location $path

    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    $dirty  = git status --porcelain 2>$null

    if (-not $NoFetch) {
        git fetch origin --quiet 2>$null
    }

    # BUG FIX: Guard against repos with no remote tracking branch before running
    # rev-list --left-right, which throws if origin/main doesn't exist yet.
    $ahead  = 0
    $behind = 0
    $hasRemoteMain = (git rev-parse --verify origin/main 2>$null) -and ($LASTEXITCODE -eq 0)

    if ($hasRemoteMain) {
        $divRaw = git rev-list --left-right --count "origin/main...HEAD" 2>$null
        if ($divRaw -match "^(\d+)\s+(\d+)$") {
            $behind = [int]$Matches[1]
            $ahead  = [int]$Matches[2]
        }
    }

    if ($branch -ne "main") {
        Warn "$repo — on branch '$branch' (expected main)"
    } elseif ($dirty) {
        $count = ($dirty -split "`n" | Where-Object { $_ }).Count
        Fail "$repo — $count uncommitted change(s) (commit or stash before proceeding)"
    } elseif ($behind -gt 0 -and $ahead -gt 0) {
        Fail "$repo — DIVERGED ($ahead ahead, $behind behind origin/main — merge required)"
    } elseif ($behind -gt 0) {
        Fail "$repo — $behind commit(s) behind origin/main (run: git pull)"
    } elseif ($ahead -gt 0) {
        Warn "$repo — $ahead unpushed commit(s)"
    } else {
        Ok "$repo — clean, on main, in sync"
    }

    # Pre-commit hook check — confirm hook is installed
    $hookFile = "$path\.git\hooks\pre-commit"
    if (Test-Path $hookFile) {
        Ok "$repo — pre-commit hook installed"
    } else {
        Warn "$repo — pre-commit hook not installed (run: python -m pre_commit install)"
    }
}

Set-Location $RepoMap["Tools"].Path

# ── HA Samba share ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "HA GREEN" -ForegroundColor White

$share          = "\\homeassistant\config\scripts"
$deployedScripts = @("ha_csv_writer.py", "ha_csv_writer_test.py")

if (Test-Path $share) {
    # Write-access test — create and remove a probe file
    $probe = "$share\_verify_probe_$PID.tmp"
    try {
        [System.IO.File]::WriteAllText($probe, "probe")
        Remove-Item $probe -Force -ErrorAction Stop
        Ok "Samba share reachable and writable"
    } catch {
        Warn "Samba share reachable but write failed — check permissions on $share"
    }

    # DEPLOY_VERSION.txt
    $versionFile = "$share\DEPLOY_VERSION.txt"
    if (Test-Path $versionFile) {
        $lastDeploy = (Get-Content $versionFile -Raw).Trim()
        Write-Host "         Last deploy: $lastDeploy" -ForegroundColor DarkGray
    } else {
        Warn "No deploy record found (run deploy-to-ha.ps1 to create one)"
    }

    # Verify expected deployed scripts are present
    foreach ($script in $deployedScripts) {
        $scriptPath = "$share\$script"
        if (Test-Path $scriptPath) {
            Ok "Deployed: $script"
        } else {
            Warn "Missing deployed file: $script (run deploy-to-ha.ps1)"
        }
    }
} else {
    Fail "Samba share not reachable: $share (open File Explorer and connect to \\homeassistant\config)"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("─" * 50) -ForegroundColor DarkGray

# BUG FIX: $total was computed but never used in the result line.
$total = $pass + $warn + $fail

if ($fail -gt 0) {
    Write-Host "RESULT: $fail failure(s), $warn warning(s), $pass passed ($total total) — resolve failures before proceeding" -ForegroundColor Red
} elseif ($warn -gt 0) {
    Write-Host "RESULT: $warn warning(s), $pass passed ($total total) — review warnings before session" -ForegroundColor Yellow
} else {
    Write-Host "RESULT: All $total checks passed — system ready" -ForegroundColor Green
}

# ── Optional JSON export ───────────────────────────────────────────────────────
if ($Json) {
    $jsonOut = [PSCustomObject]@{
        Timestamp = (Get-Date -Format 'o')
        Pass      = $pass
        Warn      = $warn
        Fail      = $fail
        Total     = $total
        Checks    = $results
    }
    $outPath = "$PSScriptRoot\verify-results.json"
    $jsonOut | ConvertTo-Json -Depth 4 | Set-Content $outPath -Encoding UTF8
    Write-Host ""
    Write-Host "Results exported to: $outPath" -ForegroundColor DarkGray
}

if ($fail -gt 0) { exit 1 }
