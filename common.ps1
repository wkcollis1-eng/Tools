# C:\repos\Tools\common.ps1
# Shared infrastructure. Dot-sourced by every script in this toolkit.
# Never run directly.
#
# Exports:
#   Assert-Environment  — pre-flight tool/auth checks
#   Test-GitRepo        — authoritative .git existence check
#   Get-Frontmatter     — YAML frontmatter parser for issue files
#   $SambaSharePath     — canonical HA share UNC path
#
# Usage:
#   . "$PSScriptRoot\common.ps1"
#   Assert-Environment                                              # git 2.x + identity
#   Assert-Environment -RequireGh                                   # + gh CLI + auth
#   Assert-Environment -RequireGh -RequirePython                    # + python 3.x
#   Assert-Environment -RequireGh -RequirePython -RequirePreCommit  # + pre-commit module
#   Assert-Environment -RequirePython -RequireSamba                 # + Samba share reachable
#   if (!(Test-GitRepo $path)) { ... }
#   $parsed = Get-Frontmatter "issues\foo.md"
#
# Version stamp — increment when this file changes.
# $CommonVersion is intentionally exported via dot-sourcing for consumers to read.
$CommonVersion = "1.3.0"

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
        Write-Host "Hard Failure: git is not installed or not on PATH. See https://git-scm.com/download/win" -ForegroundColor Red
        exit 1
    }

    # ── git minimum version (2.x required for --set-upstream, --ff-only, etc.) ─
    $gitVer = (git --version 2>$null) -replace 'git version ', ''
    if ($gitVer -and ([version]($gitVer -replace '[^0-9.].*', '').TrimEnd('.') -lt [version]"2.0")) {
        Write-Host "Hard Failure: git 2.x or later is required. Installed: $gitVer  See https://git-scm.com/download/win" -ForegroundColor Red
        exit 1
    }

    # ── git identity ──────────────────────────────────────────────────────────
    $gitName  = git config user.name  2>$null
    $gitEmail = git config user.email 2>$null
    if (-not $gitName -or -not $gitEmail) {
        Write-Host "Hard Failure: Git identity not configured. Run:`n  git config --global user.name `"Your Name`"`n  git config --global user.email `"you@example.com`"" -ForegroundColor Red
        exit 1
    }

    # ── gh CLI (optional) ─────────────────────────────────────────────────────
    if ($RequireGh) {
        if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
            Write-Host "Hard Failure: gh CLI is not installed or not on PATH. See https://cli.github.com" -ForegroundColor Red
            exit 1
        }
        $null = gh auth status 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Hard Failure: gh CLI is not authenticated. Run: gh auth login" -ForegroundColor Red
            exit 1
        }
    }

    # ── python 3.x (optional) ─────────────────────────────────────────────────
    if ($RequirePython -or $RequirePreCommit) {
        if (!(Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Host "Hard Failure: python is not installed or not on PATH. See https://python.org" -ForegroundColor Red
            exit 1
        }
        # Enforce Python 3.x minimum
        $pyVer = python -c "import sys; print(sys.version_info.major)" 2>$null
        if ($pyVer -ne "3") {
            Write-Host "Hard Failure: Python 3.x is required. Detected major version: '$pyVer'. See https://python.org" -ForegroundColor Red
            exit 1
        }
    }

    # ── pre-commit (optional) ─────────────────────────────────────────────────
    # Use 'python -m pre_commit' to avoid PATH-not-updated issue after pip install
    if ($RequirePreCommit) {
        $null = python -m pre_commit --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Hard Failure: pre-commit is not installed. Run: pip install --user pre-commit" -ForegroundColor Red
            exit 1
        }
    }

    # ── Samba share reachability (optional) ───────────────────────────────────
    if ($RequireSamba) {
        if (-not (Test-Path $SambaSharePath)) {
            Write-Host "Hard Failure: Samba share is not reachable: $SambaSharePath`nEnsure Home Assistant is running and the network share is mounted." -ForegroundColor Red
            exit 1
        }
    }
}

# ── Test-GitRepo ──────────────────────────────────────────────────────────────
# Standard .git existence check for use across all scripts.
#
# Why this exists:
#   Test-Path $path           — wrong: passes if dir exists but was never cloned
#   Test-Path "$path\.git\"   — fragile: trailing backslash variant is inconsistent
#   Test-Path "$path/.git"    — wrong separator on Windows in some edge cases
#
# This function is the single authoritative check. All batch loops (pull, push,
# status, deploy, monthly-update, etc.) must use this instead of inline variants.
#
# Returns $true only when $Path contains a valid git repository directory.
# Distinguishes three states callers care about:
#   $true   — repo is present and initialized
#   $false  — directory exists but is NOT a git repo (warn the user)
#   $false  — directory does not exist at all (also $false — caller checks as needed)
#
# Usage:
#   if (!(Test-GitRepo $repoPath)) { Write-Host "[$repo] Not cloned — skipping"; continue }
#
# ── Get-Frontmatter ───────────────────────────────────────────────────────────
# Parses the YAML frontmatter block from a local issue file.
# Used by publish-issue.ps1, list-issues.ps1, and publish-and-sync.ps1.
# Centralised here so the parser is not duplicated across those three files.
#
# Returns a PSCustomObject with:
#   .Frontmatter   — hashtable of key → value pairs from the --- block
#   .BodyStartLine — 0-based index of the first line after the closing ---
#   .Lines         — full file content as a string array (UTF-8)
#
# Usage:
#   $parsed      = Get-Frontmatter "issues\ha-config_foo.md"
#   $repo        = $parsed.Frontmatter['repo']
#   $body        = ($parsed.Lines[$parsed.BodyStartLine..($parsed.Lines.Count-1)] | Out-String).Trim()
#
function Get-Frontmatter {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $lines        = Get-Content $Path -Encoding UTF8
    $frontmatter  = @{}
    $bodyStart    = 0
    $inFM         = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i].Trim()
        if (!$inFM -and $l -eq '---') { $inFM = $true; continue }
        if ( $inFM -and $l -eq '---') { $bodyStart = $i + 1; break }
        if ( $inFM -and $l -match '^(\w+):\s*"?(.+?)"?\s*$') {
            $frontmatter[$Matches[1]] = $Matches[2]
        }
    }

    return [PSCustomObject]@{
        Frontmatter   = $frontmatter
        BodyStartLine = $bodyStart
        Lines         = $lines
    }
}

function Test-GitRepo {
    param(
        [Parameter(Mandatory)][string]$Path
    )
    # Use -PathType Container to confirm .git is a directory, not a file.
    # (A bare repo or a git worktree uses a .git file, not a directory — both
    # are unsupported by this toolkit, so treating them as "not a repo" is correct.)
    return (Test-Path (Join-Path $Path ".git") -PathType Container)
}
