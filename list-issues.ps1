# C:\repos\tools\list-issues.ps1
# Lists local issue drafts and/or open GitHub issues across managed repos.
#
# Usage:
#   .\list-issues.ps1                              # local drafts only
#   .\list-issues.ps1 -Remote                      # GitHub open issues, all repos
#   .\list-issues.ps1 -Remote -Repo home-assistant-config   # one repo only
#   .\list-issues.ps1 -All                         # local drafts + GitHub issues

param(
    [string]$Repo   = "",
    [switch]$Remote,
    [switch]$All
)

. "$PSScriptRoot\repos.ps1"

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-RepoColor($r) {
    switch ($r) {
        "home-assistant-config"                  { "Cyan" }
        "Residential-HVAC-Performance-Baseline-" { "Green" }
        "Lifepo4-Battery-Banks"                  { "Yellow" }
        "DIY-LiFePO4-UPS"                        { "Magenta" }
        "tools"                                  { "Gray" }
        default                                  { "White" }
    }
}

function Parse-Frontmatter($filePath) {
    $lines = Get-Content $filePath
    $inFM  = $false
    $meta  = @{ repo = ""; title = ""; labels = "" }
    foreach ($line in $lines) {
        $l = $line.Trim()
        if (!$inFM -and $l -eq '---') { $inFM = $true; continue }
        if ($inFM  -and $l -eq '---') { break }
        if ($inFM  -and $l -match '^(\w+):\s*"?(.+?)"?\s*$') {
            $meta[$Matches[1]] = $Matches[2]
        }
    }
    return $meta
}

# ── Local drafts ──────────────────────────────────────────────────────────────
if (!$Remote -or $All) {
    $issuesDir = "$PSScriptRoot\issues"
    Write-Host ""
    Write-Host "LOCAL DRAFTS  ($issuesDir)" -ForegroundColor White

    if (!(Test-Path $issuesDir)) {
        Write-Host "  No issues directory found. Run new-issue.ps1 to create your first draft." -ForegroundColor Yellow
    } else {
        $files = Get-ChildItem "$issuesDir\*.md" | Where-Object { $_.Name -ne "TEMPLATE.md" }
        $files = if ($Repo) { $files | Where-Object { (Parse-Frontmatter $_.FullName)['repo'] -eq $Repo } } else { $files }

        if (!$files) {
            Write-Host "  No local drafts found$(if ($Repo) { " for '$Repo'" })." -ForegroundColor Yellow
        } else {
            $localCount = 0
            foreach ($file in $files | Sort-Object Name) {
                $meta     = Parse-Frontmatter $file.FullName
                $repoVal  = if ($meta['repo'])  { $meta['repo'] }  else { "(no repo)" }
                $titleVal = if ($meta['title']) { $meta['title'] } else { "(no title)" }
                $labVal   = if ($meta['labels']) { $meta['labels'] } else { "" }

                Write-Host ""
                Write-Host "  $($file.Name)" -ForegroundColor White
                Write-Host "    Repo  : $repoVal"  -ForegroundColor (Get-RepoColor $repoVal)
                Write-Host "    Title : $titleVal" -ForegroundColor Gray
                if ($labVal) { Write-Host "    Labels: $labVal" -ForegroundColor DarkGray }
                $localCount++
            }
            Write-Host ""
            Write-Host "  $localCount draft(s). To publish: .\publish-issue.ps1 issues\<filename>" -ForegroundColor Cyan
        }
    }
}

# ── GitHub remote issues ──────────────────────────────────────────────────────
if ($Remote -or $All) {
    if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "gh CLI not found — cannot fetch remote issues. See https://cli.github.com" -ForegroundColor Red
        exit 1
    }

    $targetRepos = if ($Repo) { @($Repo) } else { $Repos }

    Write-Host ""
    Write-Host "GITHUB OPEN ISSUES" -ForegroundColor White

    $totalRemote = 0

    foreach ($r in $targetRepos) {
        $raw = gh issue list --repo "wkcollis1-eng/$r" --state open --json number,title,labels,createdAt 2>$null
        if ($LASTEXITCODE -ne 0 -or !$raw) {
            Write-Host ""
            Write-Host "  [$r] Could not fetch (repo may be private or gh not authenticated)" -ForegroundColor Yellow
            continue
        }

        $issues = $raw | ConvertFrom-Json
        if (!$issues -or $issues.Count -eq 0) {
            Write-Host ""
            Write-Host "  [$r] No open issues" -ForegroundColor Gray
            continue
        }

        Write-Host ""
        Write-Host "  [$r]" -ForegroundColor (Get-RepoColor $r)

        foreach ($issue in $issues) {
            $num    = "#$($issue.number)"
            $title  = $issue.title
            $labels = ($issue.labels | ForEach-Object { $_.name }) -join ", "
            $date   = if ($issue.createdAt) { ([datetime]$issue.createdAt).ToString("yyyy-MM-dd") } else { "" }

            Write-Host "    $num  $title" -ForegroundColor White
            if ($labels) { Write-Host "         Labels : $labels" -ForegroundColor DarkGray }
            if ($date)   { Write-Host "         Opened : $date"   -ForegroundColor DarkGray }
            $totalRemote++
        }
    }

    Write-Host ""
    Write-Host "  $totalRemote open issue(s) on GitHub." -ForegroundColor Cyan
}
