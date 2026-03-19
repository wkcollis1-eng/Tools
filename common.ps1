# C:\repos\tools\common.ps1
# Shared environment validation. Dot-sourced by every script in this toolkit.
# Never run directly.
#
# Usage in scripts:
#   . "$PSScriptRoot\common.ps1"
#   Assert-Environment              # git only
#   Assert-Environment -RequireGh   # git + gh
#   Assert-Environment -RequireGh -RequirePython  # all three

function Assert-Environment {
    param(
        [switch]$RequireGh,
        [switch]$RequirePython
    )

    # ── git (always required) ─────────────────────────────────────────────────
    if (!(Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is not installed or not on PATH. See https://git-scm.com/download/win"
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
        # Verify authenticated
        $null = gh auth status 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "gh CLI is not authenticated. Run: gh auth login"
        }
    }

    # ── python (optional) ─────────────────────────────────────────────────────
    if ($RequirePython) {
        if (!(Get-Command python -ErrorAction SilentlyContinue)) {
            throw "python is not installed or not on PATH. See https://python.org"
        }
    }
}
