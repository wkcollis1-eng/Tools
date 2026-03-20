# C:\repos\Tools\status-all-repos.ps1
# Runs git status --short in every managed repo.
# Also shows current branch, last commit, and unpushed commit count.
# Use before committing or pushing for a quick sanity check.
#
# Usage:
#   .\status-all-repos.ps1           # Normal output
#   .\status-all-repos.ps1 -Table    # Compact formatted table

param(
    [switch]$Table
)

if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not installed or not on PATH." }

. "$PSScriptRoot\repos.ps1"

$tableRows = @()

foreach ($repo in $Repos) {
    $path = $RepoMap[$repo].Path

    if (!(Test-Path "$path\.git")) {
        Write-Host ""
        Write-Host "=== $repo ===" -ForegroundColor Yellow
        Write-Host "  Not cloned" -ForegroundColor Yellow

        if ($Table) {
            $tableRows += [PSCustomObject]@{
                Repo      = $repo
                Branch    = "—"
                Unpushed  = "—"
                Changes   = "not cloned"
                LastCommit = "—"
            }
        }
        continue
    }

    Set-Location $path

    $branch   = git rev-parse --abbrev-ref HEAD 2>$null
    $unpushed = git rev-list "@{u}..HEAD" --count 2>$null

    # Safe display — null/empty means no upstream configured (new repo or detached HEAD)
    $unpushedDisplay = if ($unpushed -match '^\d+$') { $unpushed } else { "no upstream" }
    $unpushedColor   = if ($unpushed -match '^\d+$' -and [int]$unpushed -gt 0) { "Yellow" } else { "Gray" }

    $changes = git status --short

    # Last commit: short hash + subject
    $lastHash    = git rev-parse --short HEAD 2>$null
    $lastSubject = git log -1 --format="%s" 2>$null
    $lastCommit  = if ($lastHash) { "$lastHash  $lastSubject" } else { "—" }

    $branchColor = if ($branch -eq "main") { "Cyan" } else { "Yellow" }

    if (-not $Table) {
        Write-Host ""
        Write-Host "=== $repo ===" -ForegroundColor Cyan
        Write-Host "  Branch    : $branch" -ForegroundColor $branchColor
        Write-Host "  Unpushed  : $unpushedDisplay commit(s)" -ForegroundColor $unpushedColor
        Write-Host "  Last Commit: $lastCommit" -ForegroundColor DarkGray

        if ($changes) {
            Write-Host "  Changes   :" -ForegroundColor Yellow
            foreach ($line in $changes) {
                $color = if ($line -match "^\?\?") { "Gray" }
                         elseif ($line -match "^M|^A|^D") { "Green" }
                         else { "Yellow" }
                Write-Host "    $line" -ForegroundColor $color
            }
        } else {
            Write-Host "  Changes   : none" -ForegroundColor Gray
        }
    }

    if ($Table) {
        $changeCount = if ($changes) { ($changes | Measure-Object).Count } else { 0 }
        $tableRows += [PSCustomObject]@{
            Repo       = $repo
            Branch     = $branch
            Unpushed   = $unpushedDisplay
            Changes    = $changeCount
            LastCommit = $lastCommit
        }
    }
}

Set-Location $RepoMap["Tools"].Path
Write-Host ""

if ($Table) {
    $tableRows | Format-Table -AutoSize
}
