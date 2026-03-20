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
#   .\bootstrap.ps1 -ReposRoot "D:\dev\repos" -SkipPrecommit

param(
    [string]$ReposRoot = "C:\repos",
    [switch]$SkipPrecommit
)

Write-Host ""
Write-Host "BOOTSTRAP  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("═" * 50) -ForegroundColor DarkGray

# Setup logging
$bootstrapLog = Join-Path $PSScriptRoot "bootstrap.log"
function Write-Log($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Add-Content $bootstrapLog $logMessage -ErrorAction SilentlyContinue
    Write-Host $message
}

Write-Log "Bootstrap started (ReposRoot: $ReposRoot, SkipPrecommit: $SkipPrecommit)"

$toolsPath = "$ReposRoot\Tools"
$toolsUrl  = "https://github.com/wkcollis1-eng/Tools.git"

# ── Step 1: Verify prerequisites ──────────────────────────────────────────────
Write-Log ""
Write-Log "Step 1 of 6 — Checking prerequisites"

# Check Git version first
$gitVersion = git --version 2>$null
if ($gitVersion -match 'git version (\d+)\.(\d+)') {
    $major = [int]$Matches[1]
    if ($major -lt 2) {
        Write-Log "  FAIL  Git version $gitVersion - requires Git 2.x or higher"
        Write-Log "  Download latest Git from: https://git-scm.com/download/win"
        exit 1
    } else {
        Write-Log "  OK    $gitVersion"
    }
} else {
    Write-Log "  FAIL  Could not determine Git version"
    exit 1
}

$missing = @()
foreach ($cmd in @("python", "gh")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Log "  OK    $cmd"
    } else {
        Write-Log "  FAIL  $cmd not found"
        $missing += $cmd
    }
}

if ($missing.Count -gt 0) {
    Write-Log ""
    Write-Log "Install missing tools before running bootstrap:"
    if ($missing -contains "python") { Write-Log "  python: https://python.org (check 'Add to PATH')" }
    if ($missing -contains "gh") { Write-Log "  gh:     https://cli.github.com" }
    exit 1
}

# ── Step 2: gh authentication ─────────────────────────────────────────────────
Write-Log ""
Write-Log "Step 2 of 6 — GitHub CLI authentication"

$null = gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Log "  gh is not authenticated. Starting login flow..."
    gh auth login
    if ($LASTEXITCODE -ne 0) { 
        Write-Log "ERROR: gh auth login failed. Re-run bootstrap after authenticating."
        exit 1 
    }
} else {
    Write-Log "  OK    gh authenticated"
}

# ── Step 3: git identity ──────────────────────────────────────────────────────
Write-Log ""
Write-Log "Step 3 of 6 — Git identity"

$gitName  = git config --global user.name  2>$null
$gitEmail = git config --global user.email 2>$null

if ($gitName -and $gitEmail) {
    Write-Log "  OK    $gitName <$gitEmail>"
} else {
    Write-Log "  Git identity not configured."
    $name  = Read-Host "  Enter your name"
    $email = Read-Host "  Enter your email"
    git config --global user.name  $name
    git config --global user.email $email
    Write-Log "  OK    $name <$email>"
}

# ── Step 4: ExecutionPolicy ───────────────────────────────────────────────────
Write-Log ""
Write-Log "Step 4 of 6 — PowerShell execution policy"

$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @("RemoteSigned", "Unrestricted", "Bypass")) {
    Write-Log "  OK    ExecutionPolicy is $policy"
} else {
    Write-Log "  Setting ExecutionPolicy to RemoteSigned..."
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Log "  OK    ExecutionPolicy set to RemoteSigned"
}

# ── Step 5: Clone repos ───────────────────────────────────────────────────────
Write-Log ""
Write-Log "Step 5 of 6 — Clone repos"

if (!(Test-Path $ReposRoot)) {
    New-Item -Path $ReposRoot -ItemType Directory | Out-Null
    Write-Log "  Created $ReposRoot"
}

if (!(Test-Path "$toolsPath\.git")) {
    Write-Log "  Cloning Tools repo..."
    git clone $toolsUrl $toolsPath
    if ($LASTEXITCODE -ne 0) { 
        Write-Log "ERROR: Failed to clone Tools repo."
        exit 1
    }
} else {
    Write-Log "  OK    Tools repo already cloned"
}

# Unblock all scripts in the tools repo
Get-ChildItem "$toolsPath\*.ps1" | Unblock-File
Write-Log "  OK    Scripts unblocked"

# Clone remaining repos via the tools script
Set-Location $toolsPath
Write-Log "  Cloning remaining repos..."
& "$toolsPath\clone-all-repos.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Log ""
    Write-Log "WARNING: one or more repos failed to clone (see above)."
    Write-Log "Continuing bootstrap — re-run clone-all-repos.ps1 after resolving."
}

# ── Step 6: Install pre-commit hooks ─────────────────────────────────────────
Write-Log ""
Write-Log "Step 6 of 6 — Install pre-commit hooks"

if ($SkipPrecommit) {
    Write-Log "  Skipping pre-commit hooks (-SkipPrecommit)"
} else {
    # On re-runs, skip if hooks are already installed in the tools repo to avoid
    # unnecessary pre-commit autoupdate network calls on every bootstrap execution.
    $hooksAlreadyInstalled = Test-Path "$toolsPath\.git\hooks\pre-commit"
    if ($hooksAlreadyInstalled) {
        Write-Log "  OK    Pre-commit hooks already installed (skipping autoupdate)"
        Write-Log "         Run .\install-precommit-all.ps1 directly to update hook versions."
    } else {
        try {
            & "$toolsPath\install-precommit-all.ps1"
            if ($LASTEXITCODE -ne 0) { throw "install-precommit-all exited $LASTEXITCODE" }
        } catch {
            Write-Log ""
            Write-Log "WARNING: pre-commit hook installation failed: $_"
            Write-Log "Bootstrap will complete — run .\install-precommit-all.ps1 manually to retry."
        }
    }
}

# ── Verification ──────────────────────────────────────────────────────────────
Write-Log ""
Write-Log "Running verify-system.ps1 to confirm setup..."

try {
    & "$toolsPath\verify-system.ps1"
    if ($LASTEXITCODE -eq 0) {
        Write-Log ""
        Write-Log ("═" * 50)
        Write-Log "Bootstrap complete and verified!"
        Write-Log ""
        Write-Log "Ready to start work:"
        Write-Log "  cd $toolsPath"
        Write-Log "  .\session-start.ps1"
    } else {
        Write-Log ""
        Write-Log ("═" * 50)
        Write-Log "Bootstrap complete but verification failed."
        Write-Log "Review the verify-system.ps1 output above and resolve issues."
        Write-Log "Re-run: .\verify-system.ps1"
    }
} catch {
    Write-Log ""
    Write-Log ("═" * 50)
    Write-Log "Bootstrap complete but verify-system.ps1 crashed: $_"
    Write-Log "Run manually: cd $toolsPath && .\verify-system.ps1"
}

Write-Log "Bootstrap finished at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
