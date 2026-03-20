# C:\repos\tools\common.ps1
# Shared environment validation. Dot-sourced by every script in this toolkit.
# Never run directly.
#
# Usage in scripts:
#   . "$PSScriptRoot\common.ps1"
#   Assert-Environment                                        # git + identity only
#   Assert-Environment -RequireGh                            # + gh CLI + auth
#   Assert-Environment -RequireGh -RequirePython             # + python 3.x
#   Assert-Environment -RequireGh -RequirePython -RequirePreCommit  # + pre-commit
#   Assert-Environment -RequirePython -RequireSamba          # + samba share
#
# Version stamp — increment when this file changes
$CommonVersion = "1.1.0"

# Samba share path used by deploy-to-ha.ps1 and verify-system.ps1
$SambaSharePath = "\\homeassistant\config\scripts"

function Assert-Environment {
    param(
        [switch]$RequireGh,
        [switch]$RequirePython,
        [switch]$RequirePreCommit,
        [switch]$RequireSamba
    )

    # ── git (always required) ─────────────────────────────────────────────────
    if (!(Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is not installed or not on PATH. See https://git-scm.com/download/win"
    }

    # ── git minimum version (2.x required for --set-upstream, --ff-only, etc.) ─
    $gitVer = (git --version 2>$null) -replace 'git version ', ''
    if ($gitVer -and ([version]($gitVer -replace '[^0-9.].*', '') -lt [version]"2.0")) {
        throw "git 2.x or later is required. Installed: $gitVer  See https://git-scm.com/download/win"
    }

    # ── git identity ──────────────────────────────────────────────────────────
    $gitName  = git config user.name  2>$null
    $gitEmail = git config user.email 2>$null
    if (-not $gitName -or -not $gitEmail) {
        throw "Git identity not configured. Run:`n  git config --global user.name `"Your Name`"`n  git config --global user.email `"you@example.com`""
    }

    # ── gh CLI (optional) ─────────────────────────────────────────────────────
    if ($RequireGh) {
        if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
            throw "gh CLI is not installed or not on PATH. See https://cli.github.com"
        }
        $null = gh auth status 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "gh CLI is not authenticated. Run: gh auth login"
        }
    }

    # ── python 3.x (optional) ─────────────────────────────────────────────────
    if ($RequirePython -or $RequirePreCommit) {
        if (!(Get-Command python -ErrorAction SilentlyContinue)) {
            throw "python is not installed or not on PATH. See https://python.org"
        }
        # Enforce Python 3.x minimum
        $pyVer = python -c "import sys; print(sys.version_info.major)" 2>$null
        if ($pyVer -ne "3") {
            throw "Python 3.x is required. Detected major version: '$pyVer'. See https://python.org"
        }
    }

    # ── pre-commit (optional) ─────────────────────────────────────────────────
    # Use 'python -m pre_commit' to avoid PATH-not-updated issue after pip install
    if ($RequirePreCommit) {
        $null = python -m pre_commit --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "pre-commit is not installed. Run: pip install --user pre-commit"
        }
    }

    # ── Samba share reachability (optional) ───────────────────────────────────
    if ($RequireSamba) {
        if (-not (Test-Path $SambaSharePath)) {
            throw "Samba share is not reachable: $SambaSharePath`nEnsure Home Assistant is running and the network share is mounted."
        }
    }
}
