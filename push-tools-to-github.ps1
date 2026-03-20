# push-tools-to-github.ps1
#
# !! DEPRECATED — DO NOT USE !!
#
# This script was used during initial toolkit setup to copy files from a Desktop
# staging folder to C:\repos\Tools and push to GitHub. It is now superseded by:
#
#   bootstrap.ps1        — full first-time machine setup
#   sync-notes.ps1       — commit and push doc/issue changes
#   push-all-repos.ps1   — push all managed repos
#
# This file is retained for historical reference only.
# The file list is stale — many scripts added since are not included.
# Hard-coded paths (billn\OneDrive) are machine-specific and will fail elsewhere.
#
# ─────────────────────────────────────────────────────────────────────────────
# Copies tools repo files from Desktop\files to C:\repos\Tools and pushes to GitHub.
# Run this once from any PowerShell window.
#
# Usage:
#   cd C:\Users\billn\OneDrive\Desktop\files
#   .\push-tools-to-github.ps1

$source  = "C:\Users\billn\OneDrive\Desktop\files"
$target  = "C:\repos\Tools"
$repoUrl = "https://github.com/wkcollis1-eng/tools.git"

# ── Pre-flight checks ──────────────────────────────────────────────────────────
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is not installed or not on PATH."
}

if (!(Test-Path $source)) {
    throw "Source folder not found: $source"
}

# ── Clone repo if not already present ─────────────────────────────────────────
if (!(Test-Path "$target\.git")) {
    Write-Host "Cloning tools repo to $target..." -ForegroundColor Yellow
    git clone $repoUrl $target
    if ($LASTEXITCODE -ne 0) { throw "git clone failed." }
} else {
    Write-Host "Repo already exists at $target — pulling latest..." -ForegroundColor Yellow
    Set-Location $target
    git pull --quiet
}

# ── Copy files ─────────────────────────────────────────────────────────────────
# Map source filename → target filename (handles README rename)
$filemap = @{
    "repos.ps1"                = "repos.ps1"
    "clone-all-repos.ps1"      = "clone-all-repos.ps1"
    "pull-all-repos.ps1"       = "pull-all-repos.ps1"
    "push-all-repos.ps1"       = "push-all-repos.ps1"
    "status-all-repos.ps1"     = "status-all-repos.ps1"
    "deploy-to-ha.ps1"         = "deploy-to-ha.ps1"
    "install-precommit-all.ps1"= "install-precommit-all.ps1"
    "create-release.ps1"       = "create-release.ps1"
    "create-issue.ps1"         = "create-issue.ps1"
    "validate-all.ps1"         = "validate-all.ps1"
    "monthly-update.ps1"       = "monthly-update.ps1"
    "README_tools.md"          = "README.md"
}

Write-Host ""
Write-Host "Copying files..." -ForegroundColor Cyan

$copied  = 0
$missing = 0

foreach ($src in $filemap.Keys) {
    $srcPath = "$source\$src"
    $dstPath = "$target\$($filemap[$src])"

    if (!(Test-Path $srcPath)) {
        Write-Host "  MISSING: $src" -ForegroundColor Yellow
        $missing++
    } else {
        Copy-Item $srcPath $dstPath -Force
        Write-Host "  Copied:  $src -> $($filemap[$src])" -ForegroundColor Green
        $copied++
    }
}

if ($missing -gt 0) {
    Write-Host ""
    Write-Host "$missing file(s) not found in $source — check filenames and retry." -ForegroundColor Yellow
}

# ── Stage, commit, push ────────────────────────────────────────────────────────
Set-Location $target

$staged = git status --porcelain
if (!$staged) {
    Write-Host ""
    Write-Host "Nothing to commit — all files already up to date." -ForegroundColor Gray
    exit 0
}

Write-Host ""
Write-Host "Staged changes:" -ForegroundColor Cyan
git status --short

Write-Host ""
git add .
git commit -m "feat: add repos.ps1, reliability improvements across all scripts"

if ($LASTEXITCODE -ne 0) { throw "git commit failed." }

git push
if ($LASTEXITCODE -ne 0) { throw "git push failed. Check credentials (gh auth login)." }

Write-Host ""
Write-Host "Done — $copied file(s) pushed to wkcollis1-eng/tools." -ForegroundColor Cyan
