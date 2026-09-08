# C:\repos\Tools\repos.ps1
# Single source of truth for the managed repo list.
# Dot-source this in every script that iterates repos:
#   . "$PSScriptRoot\repos.ps1"
#
# To add a new repo:
#   1. Add the repo name to $Repos (alphabetical order preferred)
#   2. Add a matching entry to $RepoMap with Path and Url
#   3. No other script needs to change — all batch loops source $Repos from here
#
# Environment variable override:
#   $env:REPOS_ROOT = "D:\dev\repos"   # set before dot-sourcing to override root

# ── Configurable root ─────────────────────────────────────────────────────────
$ReposRoot = if ($env:REPOS_ROOT) { $env:REPOS_ROOT } else { "C:\repos" }

# ── Repo list ─────────────────────────────────────────────────────────────────
# FIX: "Tools" must match the GitHub repo name and local clone path exactly.
# The GitHub URL is wkcollis1-eng/Tools.git (capital T) and bootstrap clones
# to C:\repos\Tools — lowercase "tools" here caused a path mismatch.
$Repos = @(
    "DIY-LiFePO4-UPS",
    "Lifepo4-Battery-Banks",
    "Residential-HVAC-Performance-Baseline-",
    "home-assistant-config",
    "mmwave-presence-node",
    "Tools"
)

# ── Unified repo map ──────────────────────────────────────────────────────────
# Use $RepoMap[$repo].Path and $RepoMap[$repo].Url instead of constructing
# paths manually — eliminates parallel lookups and centralises casing.
$RepoMap = @{
    "DIY-LiFePO4-UPS" = @{
        Path = "$ReposRoot\DIY-LiFePO4-UPS"
        Url  = "https://github.com/wkcollis1-eng/DIY-LiFePO4-UPS.git"
    }
    "Lifepo4-Battery-Banks" = @{
        Path = "$ReposRoot\Lifepo4-Battery-Banks"
        Url  = "https://github.com/wkcollis1-eng/Lifepo4-Battery-Banks.git"
    }
    "Residential-HVAC-Performance-Baseline-" = @{
        Path = "$ReposRoot\Residential-HVAC-Performance-Baseline-"
        Url  = "https://github.com/wkcollis1-eng/Residential-HVAC-Performance-Baseline-.git"
    }
    "home-assistant-config" = @{
        Path = "$ReposRoot\home-assistant-config"
        Url  = "https://github.com/wkcollis1-eng/home-assistant-config.git"
    }
    "mmwave-presence-node" = @{
        Path = "$ReposRoot\mmwave-presence-node"
        Url  = "https://github.com/wkcollis1-eng/mmwave-presence-node.git"
    }
    "Tools" = @{
        Path = "$ReposRoot\Tools"
        Url  = "https://github.com/wkcollis1-eng/Tools.git"
    }
}

# ── Legacy compatibility shim ─────────────────────────────────────────────────
# $RepoUrls is kept so older scripts that haven't been migrated yet don't break.
# New scripts must use $RepoMap[$repo].Url instead.
$RepoUrls = @{}
foreach ($repo in $Repos) {
    $RepoUrls[$repo] = $RepoMap[$repo].Url
}

# ── Self-check ────────────────────────────────────────────────────────────────
# Catch misconfiguration (e.g. $Repos entry without matching $RepoMap key)
# at dot-source time rather than mid-loop in a batch script.
foreach ($repo in $Repos) {
    if (!$RepoMap.ContainsKey($repo)) {
        throw "repos.ps1: `$Repos contains '$repo' but `$RepoMap has no matching entry. Add it to `$RepoMap."
    }
}
if ($Repos.Count -eq 0) {
    throw "repos.ps1: `$Repos is empty. At least one repo must be defined."
}
