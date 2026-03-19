# C:\repos\tools\repos.ps1
# Single source of truth for the managed repo list.
# Dot-source this in every script that iterates repos:
#   . "$PSScriptRoot\repos.ps1"
#
# To add a repo: add one line here. No other script needs to change.

$Repos = @(
    "home-assistant-config",
    "Residential-HVAC-Performance-Baseline-",
    "Lifepo4-Battery-Banks",
    "DIY-LiFePO4-UPS",
    "tools"
)

$RepoUrls = @{
    "home-assistant-config"                  = "https://github.com/wkcollis1-eng/home-assistant-config.git"
    "Residential-HVAC-Performance-Baseline-" = "https://github.com/wkcollis1-eng/Residential-HVAC-Performance-Baseline-.git"
    "Lifepo4-Battery-Banks"                  = "https://github.com/wkcollis1-eng/Lifepo4-Battery-Banks.git"
    "DIY-LiFePO4-UPS"                        = "https://github.com/wkcollis1-eng/DIY-LiFePO4-UPS.git"
    "tools"                                  = "https://github.com/wkcollis1-eng/tools.git"
}

$ReposRoot = "C:\repos"
