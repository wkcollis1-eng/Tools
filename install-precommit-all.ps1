# C:\repos\tools\install-precommit-all.ps1
# Installs pre-commit hooks in all managed repos.
# Also runs pre-commit autoupdate to get current hook versions.
# Run once after initial clone. Safe to re-run.

if (!(Get-Command git -ErrorAction SilentlyContinue))    { throw "git is not installed or not on PATH." }
if (!(Get-Command python -ErrorAction SilentlyContinue)) { throw "python is not installed or not on PATH." }

. "$PSScriptRoot\repos.ps1"

# Install pre-commit if not present
if (!(Get-Command pre-commit -ErrorAction SilentlyContinue)) {
    Write-Host "Installing pre-commit..." -ForegroundColor Yellow
    pip install pre-commit --quiet
    if ($LASTEXITCODE -ne 0) { throw "Failed to install pre-commit." }
}

foreach ($repo in $Repos) {
    $path       = "$ReposRoot\$repo"
    $configPath = "$path\.pre-commit-config.yaml"

    if (!(Test-Path "$path\.git")) {
        Write-Host "[$repo] Not cloned — skipping" -ForegroundColor Yellow
        continue
    }

    if (!(Test-Path $configPath)) {
        Write-Host "[$repo] No .pre-commit-config.yaml — skipping" -ForegroundColor Yellow
        Write-Host "       Copy $ReposRoot\tools\.pre-commit-config.yaml to $path to enable hooks." -ForegroundColor Gray
        continue
    }

    Set-Location $path

    Write-Host "[$repo] Installing hooks..." -ForegroundColor Green
    pre-commit install --quiet

    Write-Host "[$repo] Updating hook versions..." -ForegroundColor Green
    pre-commit autoupdate

    # If autoupdate changed the config, stage it for the user
    $changed = git status --short .pre-commit-config.yaml
    if ($changed) {
        Write-Host "[$repo] Hook versions updated — commit the change:" -ForegroundColor Yellow
        Write-Host "       cd $path" -ForegroundColor Gray
        Write-Host "       git add .pre-commit-config.yaml" -ForegroundColor Gray
        Write-Host "       git commit -m 'chore: update pre-commit hook versions'" -ForegroundColor Gray
    }
}

Set-Location "$ReposRoot\tools"
Write-Host ""
Write-Host "Pre-commit hooks installed. Review any version updates above and commit." -ForegroundColor Cyan
