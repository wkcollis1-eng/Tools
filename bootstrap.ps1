# C:\repos\Tools\bootstrap.ps1
# Full first-time setup from a fresh Windows machine.
# Handles everything needed to go from zero to a working toolkit.
#
# Prerequisites (must be installed before running this script):
#   - Git 2.x:  https://git-scm.com/download/win
#   - Python 3: https://python.org (check "Add to PATH" during install)
#   - gh CLI:   https://cli.github.com
#
# Usage (run from any directory in PowerShell):
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#   cd <directory where you downloaded bootstrap.ps1>
#   Unblock-File .\bootstrap.ps1
#   .\bootstrap.ps1                          # standard
#   .\bootstrap.ps1 -ReposRoot D:\repos      # custom root
#   .\bootstrap.ps1 -SkipPrecommit           # skip pre-commit install

param(
    [string]$ReposRoot    = "C:\repos",
    [switch]$SkipPrecommit
)

# ── Bootstrap log setup ───────────────────────────────────────────────────────
$logFile = Join-Path $PSScriptRoot "bootstrap.log"
function Write-BootstrapLog {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Add-Content -Path $logFile
}

$toolsPath = "$ReposRoot\Tools"
$toolsUrl  = "https://github.com/wkcollis1-eng/Tools.git"
$failed    = $false

Write-Host ""
Write-Host "BOOTSTRAP  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-BootstrapLog "Bootstrap started. ReposRoot=$ReposRoot  SkipPrecommit=$SkipPrecommit"

# ── Step 1: Verify prerequisites ──────────────────────────────────────────────
# NOTE: common.ps1 does not exist yet (Tools not cloned), so checks are inline.
Write-Host ""
Write-Host "Step 1 of 7 — Checking prerequisites" -ForegroundColor White

$missing = @()
foreach ($cmd in @("git", "python", "gh")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Host "  OK    $cmd" -ForegroundColor Green
        Write-BootstrapLog "  prereq OK: $cmd"
    } else {
        Write-Host "  FAIL  $cmd not found" -ForegroundColor Red
        Write-BootstrapLog "  prereq FAIL: $cmd not found"
        $missing += $cmd
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "Install missing tools before running bootstrap:" -ForegroundColor Red
    if ($missing -contains "git")    { Write-Host "  git:    https://git-scm.com/download/win" }
    if ($missing -contains "python") { Write-Host "  python: https://python.org (check 'Add to PATH')" }
    if ($missing -contains "gh")     { Write-Host "  gh:     https://cli.github.com" }
    Write-BootstrapLog "ABORT: missing prerequisites: $($missing -join ', ')"
    exit 1
}

# ── Git 2.x minimum version check ────────────────────────────────────────────
$gitVerStr = (git --version 2>$null) -replace 'git version ', ''
$gitVerNum = $gitVerStr -replace '[^0-9.].*', ''
if ($gitVerNum -and ([version]$gitVerNum -lt [version]"2.0")) {
    Write-Host "  FAIL  git version too old: $gitVerStr (2.x required)" -ForegroundColor Red
    Write-Host "         https://git-scm.com/download/win" -ForegroundColor Red
    Write-BootstrapLog "ABORT: git version too old: $gitVerStr"
    exit 1
}
Write-Host "  OK    git $gitVerStr" -ForegroundColor Green

# ── Python 3.x check ─────────────────────────────────────────────────────────
$pyMajor = python -c "import sys; print(sys.version_info.major)" 2>$null
if ($pyMajor -ne "3") {
    Write-Host "  FAIL  Python 3.x required. Detected major version: '$pyMajor'" -ForegroundColor Red
    Write-BootstrapLog "ABORT: Python version check failed. Major=$pyMajor"
    exit 1
}
$pyFull = python --version 2>&1
Write-Host "  OK    $pyFull" -ForegroundColor Green

# ── Step 2: gh authentication ─────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 2 of 7 — GitHub CLI authentication" -ForegroundColor White

$null = gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  gh is not authenticated. Starting login flow..." -ForegroundColor Yellow
    gh auth login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAIL  gh auth login failed. Re-run bootstrap after authenticating." -ForegroundColor Red
        Write-BootstrapLog "ABORT: gh auth login failed"
        exit 1
    }
} else {
    Write-Host "  OK    gh authenticated" -ForegroundColor Green
    Write-BootstrapLog "  gh authenticated OK"
}

# ── Step 3: git identity ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 3 of 7 — Git identity" -ForegroundColor White

$gitName  = git config --global user.name  2>$null
$gitEmail = git config --global user.email 2>$null

if ($gitName -and $gitEmail) {
    Write-Host "  OK    $gitName <$gitEmail>" -ForegroundColor Green
    Write-BootstrapLog "  git identity OK: $gitName <$gitEmail>"
} else {
    Write-Host "  Git identity not configured." -ForegroundColor Yellow
    $name  = Read-Host "  Enter your name"
    $email = Read-Host "  Enter your email"
    git config --global user.name  $name
    git config --global user.email $email
    Write-Host "  OK    $name <$email>" -ForegroundColor Green
    Write-BootstrapLog "  git identity set: $name <$email>"
}

# ── Step 4: ExecutionPolicy ───────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 4 of 7 — PowerShell execution policy" -ForegroundColor White

$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("RemoteSigned", "Unrestricted", "Bypass")) {
    Write-Host "  OK    ExecutionPolicy is $policy" -ForegroundColor Green
} else {
    Write-Host "  Setting ExecutionPolicy to RemoteSigned..." -ForegroundColor Yellow
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host "  OK    ExecutionPolicy set to RemoteSigned" -ForegroundColor Green
    Write-BootstrapLog "  ExecutionPolicy set to RemoteSigned"
}

# ── Step 5: Clone repos ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 5 of 7 — Clone repos" -ForegroundColor White

if (!(Test-Path $ReposRoot)) {
    New-Item -Path $ReposRoot -ItemType Directory | Out-Null
    Write-Host "  Created $ReposRoot" -ForegroundColor Green
    Write-BootstrapLog "  Created ReposRoot: $ReposRoot"
}

if (!(Test-Path "$toolsPath\.git")) {
    Write-Host "  Cloning Tools repo..." -ForegroundColor Yellow
    git clone $toolsUrl $toolsPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAIL  Failed to clone Tools repo." -ForegroundColor Red
        Write-BootstrapLog "ABORT: Tools clone failed"
        exit 1
    }
    Write-BootstrapLog "  Tools repo cloned OK"
} else {
    Write-Host "  OK    Tools repo already cloned" -ForegroundColor Green
}

# Unblock all PS1 scripts in the tools repo (single backslash — correct path join)
Get-ChildItem (Join-Path $toolsPath "*.ps1") | Unblock-File
Write-Host "  OK    Scripts unblocked" -ForegroundColor Green

# Clone remaining repos via the tools script
Set-Location $toolsPath
Write-Host "  Cloning remaining repos..." -ForegroundColor Yellow
& "$toolsPath\clone-all-repos.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  WARNING: one or more repos failed to clone (see above)." -ForegroundColor Yellow
    Write-Host "           Re-run .\clone-all-repos.ps1 after resolving." -ForegroundColor Yellow
    Write-BootstrapLog "  WARNING: clone-all-repos exited $LASTEXITCODE — some repos may be missing"
    # Soft failure — continue bootstrap so pre-commit and verify can still run
}

# Now that common.ps1 is available, dot-source it for use by subsequent callers
if (Test-Path "$toolsPath\common.ps1") {
    . "$toolsPath\common.ps1"
    Write-BootstrapLog "  common.ps1 loaded (v$CommonVersion)"
}

# ── Step 6: Install pre-commit hooks ─────────────────────────────────────────
Write-Host ""
Write-Host "Step 6 of 7 — Install pre-commit hooks" -ForegroundColor White

if ($SkipPrecommit) {
    Write-Host "  SKIP  -SkipPrecommit specified." -ForegroundColor DarkGray
    Write-BootstrapLog "  Step 6 skipped (-SkipPrecommit)"
} else {
    $hooksAlreadyInstalled = Test-Path "$toolsPath\.git\hooks\pre-commit"
    if ($hooksAlreadyInstalled) {
        Write-Host "  OK    Pre-commit hooks already installed (skipping autoupdate)." -ForegroundColor Green
        Write-Host "         Run .\install-precommit-all.ps1 directly to update hook versions." -ForegroundColor Gray
    } else {
        try {
            & "$toolsPath\install-precommit-all.ps1"
            if ($LASTEXITCODE -ne 0) { throw "install-precommit-all exited $LASTEXITCODE" }
            Write-BootstrapLog "  pre-commit hooks installed OK"
        } catch {
            Write-Host "  WARNING: pre-commit hook installation failed: $_" -ForegroundColor Yellow
            Write-Host "           Run .\install-precommit-all.ps1 manually to retry." -ForegroundColor Yellow
            Write-BootstrapLog "  WARNING: pre-commit install failed: $_"
            # Soft failure — pre-commit can be installed later
        }
    }
}

# ── Step 7: Verify system ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 7 of 7 — System verification" -ForegroundColor White

$verifyScript = "$toolsPath\verify-system.ps1"
if (Test-Path $verifyScript) {
    Write-Host "  Running verify-system.ps1..." -ForegroundColor Yellow
    & $verifyScript
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: verify-system reported issues (see above)." -ForegroundColor Yellow
        Write-BootstrapLog "  verify-system exited $LASTEXITCODE — review output above"
        $failed = $true
    } else {
        Write-BootstrapLog "  verify-system passed"
    }
} else {
    Write-Host "  SKIP  verify-system.ps1 not found (run manually after session-start)." -ForegroundColor DarkGray
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray

if ($failed) {
    Write-Host "Bootstrap completed with warnings — review output above." -ForegroundColor Yellow
    Write-BootstrapLog "Bootstrap completed WITH WARNINGS"
    Write-Host "  Log: $logFile" -ForegroundColor Gray
    exit 1
} else {
    Write-Host "Bootstrap complete. Ready to work:" -ForegroundColor Green
    Write-BootstrapLog "Bootstrap completed successfully"
    Write-Host ""
    Write-Host "  cd $toolsPath" -ForegroundColor Cyan
    Write-Host "  .\session-start.ps1" -ForegroundColor Cyan
    Write-Host "  Log: $logFile" -ForegroundColor Gray
    Write-Host ""
}
