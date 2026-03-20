# C:\repos\Tools\status-all-repos.ps1
# Shows branch, last commit, unpushed commits, unpushed tags, and changed files
# for every managed repo. Use before committing or pushing.
#
# Usage:
#   .\status-all-repos.ps1          # standard per-repo output
#   .\status-all-repos.ps1 -Table   # compact formatted table

param(
    [switch]$Table
)

. "$PSScriptRoot\common.ps1"
Assert-Environment
. "$PSScriptRoot\repos.ps1"

$statusData = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($repo in $Repos) {
    $path = $RepoMap[$repo].Path

    if (!(Test-GitRepo $path)) {
        if (!$Table) {
            Write-Host ""
            Write-Host "=== $repo ===" -ForegroundColor Yellow
            Write-Host "  Not cloned (run: .\clone-all-repos.ps1)" -ForegroundColor Yellow
        }
        $statusData.Add([PSCustomObject]@{
            Repo              = $repo
            Branch            = "N/A"
            Changes           = 0
            UnpushedCommits   = 0
            UnpushedTags      = 0
            LastCommitHash    = "N/A"
            LastCommitMessage = "N/A"
            Status            = "Not cloned"
        })
        continue
    }

    # ── Gather repo state via git -C (no Set-Location) ────────────────────────
    $branch   = (git -C $path rev-parse --abbrev-ref HEAD 2>$null)
    $branch   = if ($branch) { $branch.Trim() } else { "unknown" }

    $changes  = git -C $path status --short 2>$null

    $hashFull = (git -C $path rev-parse HEAD 2>$null)
    $hash     = if ($hashFull -and $hashFull.Length -ge 8) { $hashFull.Substring(0, 8) } else { "unknown" }
    $subject  = (git -C $path log -1 --pretty=format:"%s" 2>$null)

    # Unpushed commit count — check for null before calling .Trim() to avoid
    # MethodInvocationException on repos with no upstream branch configured.
    $unpushedRaw    = git -C $path rev-list "@{u}..HEAD" --count 2>$null
    if ($null -eq $unpushedRaw -or $unpushedRaw.Trim() -eq "") {
        $unpushedCount   = 0
        $unpushedDisplay = "no upstream"
    } else {
        $unpushedCount   = [int]($unpushedRaw.Trim() -as [int])
        $unpushedDisplay = $unpushedCount
    }

    # Unpushed tags — single remote call for performance
    $unpushedTags = 0
    $hasCommits = [int]((git -C $path rev-list --count HEAD 2>$null).Trim() -as [int])
    if ($hasCommits -gt 0) {
        $localTags = git -C $path tag 2>$null
        if ($localTags) {
            $remoteTags = git -C $path ls-remote --tags origin 2>$null |
                ForEach-Object { ($_ -split '\s+')[1] -replace '^refs/tags/', '' -replace '\^\{\}$', '' }
            $unpushedTags = ($localTags | Where-Object { $_ -notin $remoteTags }).Count
        }
    }

    $changeCount = if ($changes) { ($changes | Measure-Object).Count } else { 0 }

    $overallStatus = if ($changeCount -gt 0)      { "Modified" }
                     elseif ($unpushedCount -gt 0) { "Unpushed" }
                     elseif ($unpushedTags  -gt 0) { "Unpushed" }
                     else                           { "Clean"    }

    $statusData.Add([PSCustomObject]@{
        Repo              = $repo
        Branch            = $branch
        Changes           = $changeCount
        UnpushedCommits   = $unpushedCount
        UnpushedTags      = $unpushedTags
        LastCommitHash    = $hash
        LastCommitMessage = $subject
        Status            = $overallStatus
    })

    if (!$Table) {
        $branchColor    = if ($branch -eq "main") { "Cyan" } else { "Yellow" }
        $unpushedColor  = if ($unpushedCount -gt 0) { "Yellow" } else { "Gray" }

        Write-Host ""
        Write-Host "=== $repo ===" -ForegroundColor Cyan
        Write-Host "  Branch  : $branch" -ForegroundColor $branchColor
        Write-Host "  Unpushed: $unpushedDisplay commit(s)" -ForegroundColor $unpushedColor
        if ($unpushedTags -gt 0) {
            Write-Host "  Unpushed Tags: $unpushedTags" -ForegroundColor Yellow
        }
        Write-Host "  Last    : $hash — $subject" -ForegroundColor DarkGray

        if ($changes) {
            Write-Host "  Changes :" -ForegroundColor Yellow
            foreach ($line in $changes) {
                $lineColor = if   ($line -match '^\?\?')          { "Gray"   }
                             elseif ($line -match '^[MAD]')       { "Green"  }
                             else                                  { "Yellow" }
                Write-Host "    $line" -ForegroundColor $lineColor
            }
        } else {
            Write-Host "  Changes : none" -ForegroundColor Gray
        }
    }
}

# ── Table output ──────────────────────────────────────────────────────────────
if ($Table) {
    $clean    = ($statusData | Where-Object Status -eq "Clean").Count
    $modified = ($statusData | Where-Object Status -eq "Modified").Count
    $unpushed = ($statusData | Where-Object Status -eq "Unpushed").Count
    $missing  = ($statusData | Where-Object Status -eq "Not cloned").Count

    Write-Host ""
    Write-Host "Repository Status — $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
    Write-Host "  $clean clean  $modified modified  $unpushed unpushed  $missing not cloned" -ForegroundColor Gray
    Write-Host ""

    $statusData | Format-Table -AutoSize -Wrap -Property @(
        @{ Name="Repo";       Expression={ $_.Repo };              Align="Left"  }
        @{ Name="Branch";     Expression={ $_.Branch };            Align="Left"  }
        @{ Name="Status";     Expression={ $_.Status };            Align="Left"  }
        @{ Name="Changes";    Expression={ $_.Changes };           Align="Right" }
        @{ Name="Unpushed";   Expression={ $_.UnpushedCommits };   Align="Right" }
        @{ Name="Tags";       Expression={ $_.UnpushedTags };      Align="Right" }
        @{ Name="Last Commit";Expression={ "$($_.LastCommitHash) — $($_.LastCommitMessage)" }; Align="Left" }
    )
} else {
    Write-Host ""
}
