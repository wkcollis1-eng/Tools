# C:\repos\Tools\install-precommit-all.ps1
# Installs pre-commit hooks in all managed repos.
# Also runs pre-commit autoupdate to get current hook versions.
# Run once after initial clone. Safe to re-run.
#
# Usage:
#   .\install-precommit-all.ps1               # install + autoupdate
#   .\install-precommit-all.ps1 -UpdateOnly   # autoupdate only (skip install)

param(
    [switch]$UpdateOnly
)

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequirePython
. "$PSScriptRoot\repos.ps1"

# ── Ensure pre-commit is installed ────────────────────────────────────────────
# IMPORTANT: Always use 'python -m pre_commit' (not the pre-commit binary).
# On Windows, a freshly pip-installed pre-commit binary may not be on PATH in
# the same PowerShell session.  The module invocation always works.
$null = python -m pre_commit --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "pre-commit not found — installing..." -ForegroundColor Yellow

    $pipCmd = if (Get-Command pip -ErrorAction SilentlyContinue) { "pip" }
              elseif (Get-Command pip3 -ErrorAction SilentlyContinue) { "pip3" }
              else { $null }
    if (!$pipCmd) {
        Write-Host "Neither pip nor pip3 found on PATH. Install Python with pip and retry." -ForegroundColor Red
        exit 1
    }

    # No --quiet: pip errors must be visible.
    # --user: avoids permission issues on machines without admin rights.
    & $pipCmd install --user pre-commit
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to install pre-commit via $pipCmd." -ForegroundColor Red
        exit 1
    }

    # Verify the module is now importable
    $null = python -m pre_commit --version 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "pre-commit installed but 'python -m pre_commit' still fails. Check your Python environment." -ForegroundColor Red
        exit 1
    }
}

$preCommitVer = python -m pre_commit --version 2>&1
Write-Host "Using: $preCommitVer" -ForegroundColor DarkGray

# ── Per-repo install / autoupdate ─────────────────────────────────────────────
$installFailed = @()

foreach ($repo in $Repos) {
    $path       = $RepoMap[$repo].Path
    $configPath = Join-Path $path ".pre-commit-config.yaml"

    if (!(Test-GitRepo $path)) {
        Write-Host "[$repo] Not cloned — skipping" -ForegroundColor Yellow
        continue
    }

    if (!(Test-Path $configPath)) {
        $masterConfig = Join-Path $PSScriptRoot ".pre-commit-config.yaml"
        if (Test-Path $masterConfig) {
            Write-Host "[$repo] No .pre-commit-config.yaml - distributing from Tools..." -ForegroundColor Cyan
            Copy-Item $masterConfig $configPath -Force
        } else {
            Write-Host "[$repo] No .pre-commit-config.yaml and no master copy found in Tools - skipping" -ForegroundColor Yellow
            continue
        }
    }

    # The gitleaks rule file must travel WITH the config. Without it the hook
    # falls back to stock rules, and those were measured against the 2026
    # credential leak: they caught the API key and missed the Wi-Fi PSK and the
    # OTA password. A scanner that passes on the very secrets that leaked is
    # worse than no scanner, because it reads as an all-clear.
    #
    # Always overwritten, unlike the config above which is only seeded when
    # absent: this is a shared rule set, not a per-repo preference.
    $masterLeaks = Join-Path $PSScriptRoot ".gitleaks.toml"
    if (Test-Path $masterLeaks) {
        Copy-Item $masterLeaks (Join-Path $path ".gitleaks.toml") -Force
    }

    Push-Location $path
    try {
        if (!$UpdateOnly) {
            Write-Host "[$repo] Installing hooks..." -ForegroundColor Green
            python -m pre_commit install
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[$repo] WARNING: pre-commit install failed (exit $LASTEXITCODE)" -ForegroundColor Yellow
                $installFailed += $repo
            }
        }

        Write-Host "[$repo] Updating hook versions..." -ForegroundColor Green
        python -m pre_commit autoupdate

        # If autoupdate changed the config, prompt the user to commit it
        $changed = git status --short .pre-commit-config.yaml .gitleaks.toml 2>$null
        if ($changed) {
            Write-Host "[$repo] Hook versions updated — commit the change:" -ForegroundColor Yellow
            Write-Host "       cd $path" -ForegroundColor Gray
            Write-Host "       git add .pre-commit-config.yaml .gitleaks.toml" -ForegroundColor Gray
            Write-Host "       git commit -m 'chore: update pre-commit hook versions'" -ForegroundColor Gray
        }

        # Run hooks against all files to confirm they execute correctly
        if (!$UpdateOnly) {
            Write-Host "[$repo] Running hooks to confirm installation..." -ForegroundColor DarkGray
            python -m pre_commit run --all-files
            # Non-zero exit here means a hook found issues, not that hooks are broken —
            # that's expected on first run. Report but do not fail the install.
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[$repo] NOTE: hooks ran but found issues in existing files (normal on first install)." -ForegroundColor DarkGray
            } else {
                Write-Host "[$repo] Hooks confirmed working." -ForegroundColor Green
            }
        }
    } finally {
        Pop-Location
    }
}

Set-Location $PSScriptRoot

Write-Host ""
if ($installFailed.Count -gt 0) {
    Write-Host "Pre-commit install failed for: $($installFailed -join ', ')" -ForegroundColor Red
    Write-Host "Review output above and re-run." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "Pre-commit hooks installed. Review any version updates above and commit." -ForegroundColor Cyan
}
