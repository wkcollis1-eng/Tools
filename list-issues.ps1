# C:\repos\Tools\list-issues.ps1
# Lists local issue drafts and/or open GitHub issues across managed repos.
#
# Usage:
#   .\list-issues.ps1                                          # local drafts only
#   .\list-issues.ps1 -Remote                                 # GitHub open issues, all repos
#   .\list-issues.ps1 -Remote -Repo home-assistant-config     # one repo only
#   .\list-issues.ps1 -All                                    # local drafts + GitHub issues
#   .\list-issues.ps1 -Remote -Label bug                      # filter by label
#   .\list-issues.ps1 -Remote -State closed                   # include closed issues
#   .\list-issues.ps1 -All -Export json                       # export results to JSON
#   .\list-issues.ps1 -All -Export csv                        # export results to CSV

param(
    [string]$Repo   = "",
    [string]$Label  = "",
    [string]$State  = "open",
    [string]$Export = "",     # "json" | "csv" | ""
    [switch]$Remote,
    [switch]$All
)

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\repos.ps1"

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-RepoColor($r) {
    switch ($r) {
        "home-assistant-config"                  { "Cyan" }
        "Residential-HVAC-Performance-Baseline-" { "Green" }
        "Lifepo4-Battery-Banks"                  { "Yellow" }
        "DIY-LiFePO4-UPS"                        { "Magenta" }
        "Tools"                                  { "Gray" }
        default                                  { "White" }
    }
}

function ConvertFrom-Frontmatter($filePath) {
    $lines = Get-Content $filePath -Encoding UTF8
    $inFM  = $false
    $meta  = @{ repo = ""; title = ""; labels = ""; published_url = "" }
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

# Accumulator used for -Export
$exportRows = [System.Collections.Generic.List[PSCustomObject]]::new()

# ── Local drafts ──────────────────────────────────────────────────────────────
if (!$Remote -or $All) {
    $issuesDir = "$PSScriptRoot\issues"
    Write-Host ""
    Write-Host "LOCAL DRAFTS  ($issuesDir)" -ForegroundColor White

    if (!(Test-Path $issuesDir)) {
        Write-Host "  No issues directory found. Run new-issue.ps1 to create your first draft." -ForegroundColor Yellow
    } else {
        $files = Get-ChildItem "$issuesDir\*.md" | Where-Object { $_.Name -ne "TEMPLATE.md" }
        if ($Repo) {
            $files = $files | Where-Object { (ConvertFrom-Frontmatter $_.FullName)['repo'] -eq $Repo }
        }

        if (!$files) {
            Write-Host "  No local drafts found$(if ($Repo) { " for '$Repo'" })." -ForegroundColor Yellow
        } else {
            $localCount = 0
            foreach ($file in $files | Sort-Object Name) {
                $meta     = ConvertFrom-Frontmatter $file.FullName
                $repoVal  = if ($meta['repo'])   { $meta['repo'] }   else { "(no repo)" }
                $titleVal = if ($meta['title'])  { $meta['title'] }  else { "(no title)" }
                $labVal   = if ($meta['labels']) { $meta['labels'] } else { "" }
                $pubUrl   = $meta['published_url']

                # Filter by label if specified
                if ($Label -and $labVal -notmatch [regex]::Escape($Label)) { continue }

                Write-Host ""
                Write-Host "  $($file.Name)$(if ($pubUrl) { '  [published]' })" -ForegroundColor White
                Write-Host "    Repo  : $repoVal"  -ForegroundColor (Get-RepoColor $repoVal)
                Write-Host "    Title : $titleVal" -ForegroundColor Gray
                if ($labVal) { Write-Host "    Labels: $labVal" -ForegroundColor DarkGray }
                if ($pubUrl) { Write-Host "    URL   : $pubUrl"  -ForegroundColor DarkGray }
                $localCount++

                if ($Export) {
                    $exportRows.Add([PSCustomObject]@{
                        Source   = "local"
                        Repo     = $repoVal
                        Number   = ""
                        Title    = $titleVal
                        Labels   = $labVal
                        Opened   = ""
                        Published = $pubUrl
                        File     = $file.Name
                    })
                }
            }
            Write-Host ""
            Write-Host "  $localCount draft(s). To publish: .\publish-issue.ps1 issues\<filename>" -ForegroundColor Cyan
        }
    }
}

# ── GitHub remote issues ──────────────────────────────────────────────────────
if ($Remote -or $All) {
    Assert-Environment -RequireGh

    $targetRepos = if ($Repo) { @($Repo) } else { $Repos }

    Write-Host ""
    Write-Host "GITHUB $(($State).ToUpper()) ISSUES" -ForegroundColor White

    $totalRemote = 0

    foreach ($r in $targetRepos) {
        $ghArgs = @("issue", "list", "--repo", "wkcollis1-eng/$r",
                    "--state", $State, "--json", "number,title,labels,createdAt")
        if ($Label) { $ghArgs += @("--label", $Label) }

        $raw = & gh @ghArgs 2>$null
        if ($LASTEXITCODE -ne 0 -or !$raw) {
            Write-Host ""
            Write-Host "  [$r] Could not fetch (repo may be private or gh not authenticated)" -ForegroundColor Yellow
            continue
        }

        $issues = $raw | ConvertFrom-Json
        if (!$issues -or $issues.Count -eq 0) {
            Write-Host ""
            Write-Host "  [$r] No $State issues" -ForegroundColor DarkGray
            continue
        }

        Write-Host ""
        Write-Host "  [$r]" -ForegroundColor (Get-RepoColor $r)

        foreach ($issue in $issues) {
            $num    = "#$($issue.number)"
            $title  = $issue.title
            $labels = ($issue.labels | ForEach-Object { $_.name }) -join ", "

            # BUG FIX: safe cast — ([datetime]$issue.createdAt) throws on null/unexpected format
            $dt     = $issue.createdAt -as [datetime]
            $date   = if ($dt) { $dt.ToString("yyyy-MM-dd") } else { "unknown" }

            Write-Host "    $num  $title" -ForegroundColor White
            if ($labels) { Write-Host "         Labels : $labels" -ForegroundColor DarkGray }
            Write-Host "         Opened : $date" -ForegroundColor DarkGray
            $totalRemote++

            if ($Export) {
                $exportRows.Add([PSCustomObject]@{
                    Source    = "github"
                    Repo      = $r
                    Number    = $issue.number
                    Title     = $title
                    Labels    = $labels
                    Opened    = $date
                    Published = ""
                    File      = ""
                })
            }
        }
    }

    Write-Host ""
    Write-Host "  $totalRemote $State issue(s) on GitHub." -ForegroundColor Cyan
}

# ── Export ────────────────────────────────────────────────────────────────────
if ($Export -and $exportRows.Count -gt 0) {
    $stamp    = Get-Date -Format "yyyyMMdd-HHmm"
    $outDir   = $PSScriptRoot

    switch ($Export.ToLower()) {
        "json" {
            $outFile = "$outDir\issues-export-$stamp.json"
            $exportRows | ConvertTo-Json -Depth 3 | Set-Content $outFile -Encoding UTF8
            Write-Host "Exported $($exportRows.Count) row(s) → $outFile" -ForegroundColor Cyan
        }
        "csv" {
            $outFile = "$outDir\issues-export-$stamp.csv"
            $exportRows | Export-Csv $outFile -NoTypeInformation -Encoding UTF8
            Write-Host "Exported $($exportRows.Count) row(s) → $outFile" -ForegroundColor Cyan
        }
        default {
            Write-Host "Unknown -Export format '$Export'. Use 'json' or 'csv'." -ForegroundColor Yellow
        }
    }
}
