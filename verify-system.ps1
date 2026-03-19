# C:\repos\tools\verify-system.ps1
# Full environment health check. Run at the start of any session to confirm
# the system is in a known-good state before doing real work.
#
# Checks:
#   - git, gh, python installed and configured
#   - All repos cloned and on main branch
#   - All working trees clean
#   - HA Samba share reachable
#
# Usage:
#   .\verify-system.ps1

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\repos.ps1"

$pass    = 0
$warn    = 0
$fail    = 0

function Ok($msg)   { Write-Host "  OK    $msg" -ForegroundColor Green;  $script:pass++ }
function Warn($msg) { Write-Host "  WARN  $msg" -ForegroundColor Yellow; $script:warn++ }
function Fail($msg) { Write-Host "  FAIL  $msg" -ForegroundColor Red;    $script:fail++ }

Write-Host ""
Write-Host "System Verification  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("─" * 50) -ForegroundColor DarkGray

# ── Tools ─────────────────────────────────────────────────────────────────────
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
    $path = "$ReposRoot\$repo"

    if (!(Test-Path "$path\.git")) {
        Fail "$repo — not cloned (run: .\clone-all-repos.ps1)"
        continue
    }

    Set-Location $path

    $branch   = git rev-parse --abbrev-ref HEAD 2>$null
    $dirty    = git status --porcelain 2>$null
    $unpushed = git rev-list "@{u}..HEAD" --count 2>$null

    if ($branch -ne "main") {
        Warn "$repo — on branch '$branch' (expected main)"
    } elseif ($dirty) {
        $count = ($dirty -split "`n" | Where-Object { $_ }).Count
        Warn "$repo — $count uncommitted change(s)"
    } elseif ([int]$unpushed -gt 0) {
        Warn "$repo — $unpushed unpushed commit(s)"
    } else {
        Ok "$repo — clean, on main"
    }
}

Set-Location "$ReposRoot\tools"

# ── HA Samba share ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "HA GREEN" -ForegroundColor White

$share = "\\homeassistant\config\scripts"
if (Test-Path $share) {
    # Check for DEPLOY_VERSION.txt if present
    $versionFile = "$share\DEPLOY_VERSION.txt"
    if (Test-Path $versionFile) {
        $lastDeploy = Get-Content $versionFile -Raw
        Ok "Samba share reachable — last deploy: $($lastDeploy.Trim())"
    } else {
        Ok "Samba share reachable (no deploy record yet)"
    }
} else {
    Fail "Samba share not reachable: $share (open File Explorer and connect to \\homeassistant\config)"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("─" * 50) -ForegroundColor DarkGray
$total = $pass + $warn + $fail

if ($fail -gt 0) {
    Write-Host "RESULT: $fail failure(s), $warn warning(s), $pass passed — resolve failures before proceeding" -ForegroundColor Red
    exit 1
} elseif ($warn -gt 0) {
    Write-Host "RESULT: $warn warning(s), $pass passed — review warnings before session" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "RESULT: All $pass checks passed — system ready" -ForegroundColor Green
    exit 0
}
