# C:\repos\Tools\bootstrap.ps1
# Full first-time setup from a fresh Windows machine.
# Handles everything needed to go from zero to a working toolkit.
#
# Prerequisites (must be installed before running this script):
#   - Git:    https://git-scm.com/download/win
#   - Python: https://python.org (check "Add to PATH" during install)
#   - gh CLI: https://cli.github.com
#
# Usage (run from any directory in PowerShell):
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#   cd <directory where you downloaded bootstrap.ps1>
#   Unblock-File .\bootstrap.ps1
#   .\bootstrap.ps1

Write-Host ""
Write-Host "BOOTSTRAP  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray

$reposRoot = "C:\repos"
$toolsPath = "$reposRoot\Tools"
$toolsUrl  = "https://github.com/wkcollis1-eng/Tools.git"

# ── Step 1: Verify prerequisites ──────────────────────────────────────────────
Write-Host ""
Write-Host "Step 1 of 6 — Checking prerequisites" -ForegroundColor White

$missing = @()
foreach ($cmd in @("git", "python", "gh")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Host "  OK    $cmd" -ForegroundColor Green
    } else {
        Write-Host "  FAIL  $cmd not found" -ForegroundColor Red
        $missing += $cmd
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "Install missing tools before running bootstrap:" -ForegroundColor Red
    if ($missing -contains "git")    { Write-Host "  git:    https://git-scm.com/download/win" }
    if ($missing -contains "python") { Write-Host "  python: https://python.org (check 'Add to PATH')" }
    if ($missing -contains "gh")     { Write-Host "  gh:     https://cli.github.com" }
    exit 1
}

# ── Step 2: gh authentication ─────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 2 of 6 — GitHub CLI authentication" -ForegroundColor White

$null = gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  gh is not authenticated. Starting login flow..." -ForegroundColor Yellow
    gh auth login
    if ($LASTEXITCODE -ne 0) { throw "gh auth login failed. Re-run bootstrap after authenticating." }
} else {
    Write-Host "  OK    gh authenticated" -ForegroundColor Green
}

# ── Step 3: git identity ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 3 of 6 — Git identity" -ForegroundColor White

$gitName  = git config --global user.name  2>$null
$gitEmail = git config --global user.email 2>$null

if ($gitName -and $gitEmail) {
    Write-Host "  OK    $gitName <$gitEmail>" -ForegroundColor Green
} else {
    Write-Host "  Git identity not configured." -ForegroundColor Yellow
    $name  = Read-Host "  Enter your name"
    $email = Read-Host "  Enter your email"
    git config --global user.name  $name
    git config --global user.email $email
    Write-Host "  OK    $name <$email>" -ForegroundColor Green
}

# ── Step 4: ExecutionPolicy ───────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 4 of 6 — PowerShell execution policy" -ForegroundColor White

$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("RemoteSigned", "Unrestricted", "Bypass")) {
    Write-Host "  OK    ExecutionPolicy is $policy" -ForegroundColor Green
} else {
    Write-Host "  Setting ExecutionPolicy to RemoteSigned..." -ForegroundColor Yellow
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host "  OK    ExecutionPolicy set to RemoteSigned" -ForegroundColor Green
}

# ── Step 5: Clone repos ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "Step 5 of 6 — Clone repos" -ForegroundColor White

if (!(Test-Path $reposRoot)) {
    New-Item -Path $reposRoot -ItemType Directory | Out-Null
    Write-Host "  Created $reposRoot" -ForegroundColor Green
}

if (!(Test-Path "$toolsPath\.git")) {
    Write-Host "  Cloning Tools repo..." -ForegroundColor Yellow
    git clone $toolsUrl $toolsPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to clone Tools repo." }
} else {
    Write-Host "  OK    Tools repo already cloned" -ForegroundColor Green
}

# Unblock all scripts in the tools repo
Get-ChildItem "$toolsPath\*.ps1" | Unblock-File
Write-Host "  OK    Scripts unblocked" -ForegroundColor Green

# Clone remaining repos via the tools script
Set-Location $toolsPath
Write-Host "  Cloning remaining repos..." -ForegroundColor Yellow
& "$toolsPath\clone-all-repos.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "WARNING: one or more repos failed to clone (see above)." -ForegroundColor Yellow
    Write-Host "Continuing bootstrap — re-run clone-all-repos.ps1 after resolving." -ForegroundColor Yellow
}

# ── Step 6: Install pre-commit hooks ─────────────────────────────────────────
Write-Host ""
Write-Host "Step 6 of 6 — Install pre-commit hooks" -ForegroundColor White

# On re-runs, skip if hooks are already installed in the tools repo to avoid
# unnecessary pre-commit autoupdate network calls on every bootstrap execution.
$hooksAlreadyInstalled = Test-Path "$toolsPath\.git\hooks\pre-commit"
if ($hooksAlreadyInstalled) {
    Write-Host "  OK    Pre-commit hooks already installed (skipping autoupdate)" -ForegroundColor Green
    Write-Host "         Run .\install-precommit-all.ps1 directly to update hook versions." -ForegroundColor Gray
} else {
    try {
        & "$toolsPath\install-precommit-all.ps1"
        if ($LASTEXITCODE -ne 0) { throw "install-precommit-all exited $LASTEXITCODE" }
    } catch {
        Write-Host ""
        Write-Host "WARNING: pre-commit hook installation failed: $_" -ForegroundColor Yellow
        Write-Host "Bootstrap will complete — run .\install-precommit-all.ps1 manually to retry." -ForegroundColor Yellow
    }
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("═" * 50) -ForegroundColor DarkGray
Write-Host "Bootstrap complete. Run verify-system.ps1 to confirm:" -ForegroundColor Green
Write-Host ""
Write-Host "  cd C:\repos\Tools" -ForegroundColor Cyan
Write-Host "  .\verify-system.ps1" -ForegroundColor Cyan
Write-Host "  .\session-start.ps1" -ForegroundColor Cyan
Write-Host ""
