# C:\repos\Tools\repos.ps1
# Single source of truth for the managed repo list.
# Dot-source this in every script that iterates repos:
#   . "$PSScriptRoot\repos.ps1"
#
# ── How to add a repo ────────────────────────────────────────────────────────
# 1. Add the repo name (match GitHub repo name exactly) to $Repos.
# 2. Add a matching entry to $RepoUrls.
# 3. $RepoMap is rebuilt automatically — no other changes needed.
# No other script needs to change.
# ─────────────────────────────────────────────────────────────────────────────

# Root directory that contains all cloned repos.
# Override by setting $env:REPOS_ROOT before dot-sourcing this file.
$ReposRoot = if ($env:REPOS_ROOT) { $env:REPOS_ROOT } else { "C:\repos" }

# Ordered list of managed repos (names must match GitHub repo names exactly).
$Repos = @(
    "home-assistant-config",
    "Residential-HVAC-Performance-Baseline-",
    "Lifepo4-Battery-Banks",
    "DIY-LiFePO4-UPS",
    "Tools"
)

# GitHub clone URLs keyed by repo name.
$RepoUrls = @{
    "home-assistant-config"                  = "https://github.com/wkcollis1-eng/home-assistant-config.git"
    "Residential-HVAC-Performance-Baseline-" = "https://github.com/wkcollis1-eng/Residential-HVAC-Performance-Baseline-.git"
    "Lifepo4-Battery-Banks"                  = "https://github.com/wkcollis1-eng/Lifepo4-Battery-Banks.git"
    "DIY-LiFePO4-UPS"                        = "https://github.com/wkcollis1-eng/DIY-LiFePO4-UPS.git"
    "Tools"                                  = "https://github.com/wkcollis1-eng/Tools.git"
}

# Unified map — use $RepoMap[$repo].Path and $RepoMap[$repo].Url
# instead of parallel lookups into $Repos + $RepoUrls.
$RepoMap = @{}
foreach ($repo in $Repos) {
    $RepoMap[$repo] = [PSCustomObject]@{
        Name = $repo
        Path = Join-Path $ReposRoot $repo
        Url  = $RepoUrls[$repo]
    }
}
