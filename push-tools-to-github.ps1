# push-tools-to-github.ps1
#
# !! DEPRECATED — DO NOT USE !!
#
# This script was used during initial toolkit setup to stage files from a Desktop
# folder and push to GitHub. It is retained for historical reference only.
#
# SUPERSEDED BY:
#   bootstrap.ps1        — full first-time machine setup
#   sync-notes.ps1       — commit and push doc/issue changes
#   push-all-repos.ps1   — push all managed repos
#
# WHY IT CANNOT BE USED:
#   - Hard-coded path (C:\Users\billn\OneDrive\...) is machine-specific
#   - File list is stale — many scripts added since are not included
#   - Clones to tools.git (lowercase) — conflicts with current Tools casing
#
# If you are reading this and wondering whether to run it: do not.
# Run bootstrap.ps1 instead.

Write-Host "DEPRECATED: push-tools-to-github.ps1 must not be used." -ForegroundColor Red
Write-Host "Use bootstrap.ps1 for first-time setup, or sync-notes.ps1 / push-all-repos.ps1 for day-to-day work." -ForegroundColor Yellow
exit 1

# ─── Historical code below — not executed ─────────────────────────────────────
<#
$source  = "C:\Users\billn\OneDrive\Desktop\files"
$target  = "C:\repos\Tools"
$repoUrl = "https://github.com/wkcollis1-eng/tools.git"
... (retained for reference only)
#>
