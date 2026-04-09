# C:\repos\Tools\monthly-update.ps1
# Orchestrates the full 1st-of-month data update workflow:
#   1. Pull all repos
#   2. Pull HA data — copy CSV reports from HA Green + read billing archives via REST API
#   3. Validate HVAC baseline data for the PRIOR month (Phase 1: only warn, Phase 2: halt on failure)
#   4. Open an issue in the target repo as a work queue item (optional)
#   5. After Claude Code session: validate current month, tag releases, push
#
# Usage:
#   .\monthly-update.ps1 -Month 2026-03 -Phase 1
#   .\monthly-update.ps1 -Month 2026-03 -Phase 2 -Tag v2026.03.1
#   .\monthly-update.ps1 -Month 2026-03 -Phase 2 -Tag v2026.03.1 -SkipRelease
#   .\monthly-update.ps1 -Month 2026-03 -Phase 1 -SkipHaPull

param(
    [Parameter(Mandatory)][string]$Month,
    [Parameter(Mandatory)][ValidateSet("1","2")][string]$Phase,
    [string]$Tag = "",
    [switch]$SkipRelease,
    [switch]$DraftRelease,
    [switch]$SkipHaPull
)

. "$PSScriptRoot\common.ps1"
Assert-Environment -RequireGh -RequirePython

. "$PSScriptRoot\repos.ps1"

# ── Month format validation ────────────────────────────────────────────────────
if ($Month -match '^\d{4}-\d{2}-\d{2}$') {
    $Month = $Month.Substring(0, 7)
}
if ($Month -notmatch '^\d{4}-\d{2}$') {
    Write-Host "Invalid month format '$Month'. Use YYYY-MM." -ForegroundColor Red
    exit 1
}

$monthDisplay = $Month
$year  = $Month.Split('-')[0]
$mo    = $Month.Split('-')[1]

$monthDate  = [datetime]::ParseExact($Month, "yyyy-MM", $null)
$priorMonth = $monthDate.AddMonths(-1).ToString("yyyy-MM")

$monthNames = @{
    "01"="jan"; "02"="feb"; "03"="mar"; "04"="apr";
    "05"="may"; "06"="jun"; "07"="jul"; "08"="aug";
    "09"="sep"; "10"="oct"; "11"="nov"; "12"="dec"
}
$priorMo     = $monthDate.AddMonths(-1).ToString("MM")
$priorSlot   = $monthNames[$priorMo]
$currentSlot = $monthNames[$mo]

$releaseRepos = $Repos | Where-Object { $_ -ne "Tools" }

$sambaRoot  = "\\homeassistant\config"
$haReports  = "$sambaRoot\reports"
$hvacRepo   = "$ReposRoot\Residential-HVAC-Performance-Baseline-"
$repoReport = "$hvacRepo\homeassistant\reports"

$haUrl   = if ($env:HA_URL) { $env:HA_URL } else { "http://homeassistant.local:8123" }
$haToken = $env:HA_TOKEN

function Step($msg) {
    Write-Host ""
    Write-Host "── $msg" -ForegroundColor Cyan
}

function Abort($msg) {
    Write-Host ""
    Write-Host "ABORTED: $msg" -ForegroundColor Red
    exit 1
}

function RunValidation($monthArg, [switch]$HaltOnFailure) {
    Step "Validating HVAC baseline data ($monthArg)"
    & "$PSScriptRoot\validate-all.ps1" -Month $monthArg
    if ($HaltOnFailure -and $LASTEXITCODE -ne 0) {
        Abort "Validation HALT — fix data errors before proceeding."
    } elseif ($LASTEXITCODE -ne 0) {
        Write-Host "  Validation completed with issues — continue with Claude Code to fix." -ForegroundColor Yellow
    }
}

if ($Phase -eq "2" -and -not $SkipRelease -and $Tag -ne "") {
    if ($Tag -notmatch '^v\d{4}\.\d{2}\.\d+$') {
        Write-Host "Invalid tag format: '$Tag'" -ForegroundColor Red
        Write-Host "Expected CalVer format: vYYYY.MM.N  (e.g. v$year.$mo.1)" -ForegroundColor Yellow
        exit 1
    }
}

function Invoke-HaDataPull {
    param([string]$TargetMonth)

    Write-Host ""
    Write-Host "  ── HA CSV Reports (Samba)" -ForegroundColor DarkCyan

    $csvMappings = @(
        @{ Label = "hvac_monthly.csv"; Source = "$haReports\hvac_monthly.csv"; Dest = "$repoReport\hvac_monthly.csv"; DateKey = "month" },
        @{ Label = "utility_monthly.csv"; Source = "$haReports\utility_monthly.csv"; Dest = "$repoReport\utility_monthly.csv"; DateKey = "month" }
    )
    $dailyYear = $TargetMonth.Substring(0,4)
    $csvMappings += @{ Label = "hvac_daily_$dailyYear.csv"; Source = "$haReports\hvac_daily_$dailyYear.csv"; Dest = "$repoReport\hvac_daily_$dailyYear.csv"; DateKey = "date" }

    $sambaOk = Test-Path $haReports -ErrorAction SilentlyContinue
    if (-not $sambaOk) {
        Write-Host "  WARN: HA Green Samba share unreachable ($haReports) — skipping CSV copy" -ForegroundColor Yellow
    } else {
        foreach ($map in $csvMappings) {
            if (-not (Test-Path $map.Source)) {
                Write-Host ("  WARN: Source not found: {0}" -f $map.Source) -ForegroundColor Yellow
                continue
            }
            $destDir = Split-Path $map.Dest -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            $srcRows = Import-Csv $map.Source
            $destRows = if (Test-Path $map.Dest) { Import-Csv $map.Dest } else { @() }
            $existing = $destRows | ForEach-Object { $_."$($map.DateKey)" }
            $newRows = $srcRows | Where-Object { $existing -notcontains $_."$($map.DateKey)" }
            if ($newRows.Count -gt 0) {
                $newRows | Export-Csv $map.Dest -Append -NoTypeInformation
                Write-Host ("  ADDED  {0,-28}  +{1} row(s)" -f $map.Label, $newRows.Count) -ForegroundColor Green
            } else {
                Write-Host ("  OK     {0,-28}  up to date" -f $map.Label) -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
    Write-Host "  ── Billing Archives (HA REST API — prior month: $priorSlot)" -ForegroundColor DarkCyan

    if (-not $haToken) {
        Write-Host "  SKIP: `$env:HA_TOKEN not set — billing archive pull skipped." -ForegroundColor Yellow
        Write-Host "        Set token and re-run, or enter billing data manually in Claude Code." -ForegroundColor DarkGray
        return
    }

    $billingEntities = @(
        "input_number.gas_archive_${priorSlot}_ccf"
        "input_number.electric_archive_${priorSlot}_kwh"
        "input_number.electric_archive_${priorSlot}_amount"
        "input_number.dhw_archive_${currentSlot}"
    )

    $headers = @{ "Authorization" = "Bearer $haToken"; "Content-Type" = "application/json" }
    $entityValues = @{}
    $missingEntities = @()

    foreach ($entity in $billingEntities) {
        try {
            $resp = Invoke-RestMethod -Uri "$haUrl/api/states/$entity" -Headers $headers -TimeoutSec 10
            $val = $resp.state
            if ($val -eq "unavailable" -or $val -eq "unknown") {
                Write-Host ("  WARN: {0} = {1}" -f $entity, $val) -ForegroundColor Yellow
                $missingEntities += $entity
                $entityValues[$entity] = $null
            } else {
                $entityValues[$entity] = [double]$val
                Write-Host ("  READ   {0,-50}  = {1}" -f $entity, $val) -ForegroundColor DarkGray
            }
        } catch {
            Write-Host ("  WARN: Could not read {0} ({1})" -f $entity, $_.Exception.Message) -ForegroundColor Yellow
            $missingEntities += $entity
            $entityValues[$entity] = $null
        }
    }

    # Always write rows, even with missing values
    $dataDir = "$hvacRepo\data"
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

    function Append-UtilityRow {
        param(
            [string]$FilePath,
            [PSCustomObject]$Row,
            [string]$KeyColumn,
            [string]$KeyValue
        )
        if (-not (Test-Path $FilePath)) {
            $Row | Export-Csv $FilePath -NoTypeInformation
            Write-Host ("  ADDED  {0,-30} +1 row for {1}" -f (Split-Path $FilePath -Leaf), $KeyValue) -ForegroundColor Green
            return
        }
        $existingRows = Import-Csv $FilePath
        $alreadyHas = $existingRows | Where-Object { $_."$KeyColumn" -eq $KeyValue }
        if ($alreadyHas) {
            Write-Host ("  OK     {0} already has row for {1}" -f (Split-Path $FilePath -Leaf), $KeyValue) -ForegroundColor DarkGray
            return
        }
        $Row | Export-Csv $FilePath -Append -NoTypeInformation
        Write-Host ("  ADDED  {0,-30} +1 row for {1}" -f (Split-Path $FilePath -Leaf), $KeyValue) -ForegroundColor Green
    }

    $priorMonthWithDay = "$priorMonth-01"

    $gasRow = [PSCustomObject]@{ month = $priorMonthWithDay; ccf = $entityValues["input_number.gas_archive_${priorSlot}_ccf"] }
    Append-UtilityRow -FilePath "$dataDir\monthly_gas_scg.csv" -Row $gasRow -KeyColumn "month" -KeyValue $priorMonthWithDay

    $elecRow = [PSCustomObject]@{ month = $priorMonthWithDay; kwh = $entityValues["input_number.electric_archive_${priorSlot}_kwh"]; amount = $entityValues["input_number.electric_archive_${priorSlot}_amount"] }
    Append-UtilityRow -FilePath "$dataDir\monthly_electricity_eversource.csv" -Row $elecRow -KeyColumn "month" -KeyValue $priorMonthWithDay

    $dhwRow = [PSCustomObject]@{ month = $priorMonthWithDay; ccf = $entityValues["input_number.dhw_archive_${currentSlot}"] }
    Append-UtilityRow -FilePath "$dataDir\monthly_dhw_navien.csv" -Row $dhwRow -KeyColumn "month" -KeyValue $priorMonthWithDay

    if ($missingEntities.Count -gt 0) {
        Write-Host "  WARNING: Some billing data missing. Rows written with empty fields. Fill manually in Claude Code." -ForegroundColor Yellow
        Write-Host "    Missing: $($missingEntities -join ', ')" -ForegroundColor DarkGray
    } else {
        Write-Host "  Billing data written to $dataDir" -ForegroundColor DarkGray
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 1
# ═════════════════════════════════════════════════════════════════════════════
if ($Phase -eq "1") {
    Write-Host ""
    Write-Host "Monthly Update — Phase 1 ($monthDisplay)" -ForegroundColor White

    Step "Pulling all repos"
    & "$PSScriptRoot\pull-all-repos.ps1"

    Step "Checking git status before session"
    & "$PSScriptRoot\status-all-repos.ps1"

    if ($SkipHaPull) {
        Step "HA data pull (skipped — -SkipHaPull)"
    } else {
        Step "Pulling HA data → repo CSVs ($monthDisplay)"
        Invoke-HaDataPull -TargetMonth $monthDisplay
    }

    # Validate prior month but do NOT halt on failure (Phase 1 is for data capture)
    RunValidation $priorMonth -HaltOnFailure:$false

    Step "Creating work queue issue"
    $issueTitle = "Monthly data update — $monthDisplay"
    $issueBody = @"
Monthly utility bill entry and data update for $monthDisplay.

Checklist:
- [ ] Enter gas bill (monthly_gas_scg.csv)
- [ ] Enter electricity bill (monthly_electricity_eversource.csv)
- [ ] Enter DHW reading (monthly_dhw_navien.csv)
- [ ] Update monthly_summary.csv
- [ ] Update monthly_hvac_runtime.csv
- [ ] Run validate-all.ps1 -Month $monthDisplay
- [ ] Commit and tag releases
"@

    Write-Host "Creating issue in Residential-HVAC-Performance-Baseline-..." -ForegroundColor Green
    $issueRaw = & gh issue create --repo wkcollis1-eng/Residential-HVAC-Performance-Baseline- --title $issueTitle --body $issueBody
    $issueUrl = $issueRaw | Where-Object { $_ -match '^https://' } | Select-Object -First 1
    if ($LASTEXITCODE -eq 0 -and $issueUrl) {
        Write-Host "Issue created: $issueUrl" -ForegroundColor Cyan
    } else {
        Write-Host "Issue creation failed or URL not returned (gh error) — continuing." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Phase 1 complete. Run your Claude Code session now." -ForegroundColor White
    Write-Host "When done, run: .\monthly-update.ps1 -Month $monthDisplay -Phase 2 -Tag v$year.$mo.1" -ForegroundColor Yellow
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 2
# ═════════════════════════════════════════════════════════════════════════════
if ($Phase -eq "2") {
    Write-Host ""
    Write-Host "Monthly Update — Phase 2 ($monthDisplay)" -ForegroundColor White

    if (-not $SkipRelease -and $Tag -eq "") {
        Abort "-Tag is required for Phase 2 unless -SkipRelease is set. Example: -Tag v$year.$mo.1"
    }

    Step "Checking git status after session"
    & "$PSScriptRoot\status-all-repos.ps1"

    foreach ($repo in $releaseRepos) {
        $path = "$ReposRoot\$repo"
        if (!(Test-GitRepo $path)) { continue }
        $dirty = git -C $path status --porcelain
        if ($dirty) {
            Abort "Uncommitted changes in $repo. Commit or stash before running Phase 2."
        }
    }

    # Validate current month with HALT on failure (strict pre-release gate)
    RunValidation $monthDisplay -HaltOnFailure

    if (-not $SkipRelease) {
        Step "Creating releases ($Tag)"
        $releaseTitle = "$monthDisplay monthly update"
        $releaseNotes = "Monthly data update for $monthDisplay."

        foreach ($repo in $releaseRepos) {
            $repoPath = "$ReposRoot\$repo"
            if (-not (Test-GitRepo $repoPath)) {
                Write-Host "  Skipping $repo (not cloned locally)" -ForegroundColor Yellow
                continue
            }
            $lastTag = (git -C $repoPath describe --tags --abbrev=0 2>$null)
            $lastTag = if ($lastTag) { $lastTag.Trim() } else { $null }
            $commitsSince = if ($lastTag) { git -C $repoPath rev-list "$lastTag..HEAD" --count 2>$null } else { git -C $repoPath rev-list HEAD --count 2>$null }
            $commitCount = [int]($commitsSince.Trim() -as [int])
            if ($commitCount -gt 0) {
                $sinceMsg = if ($lastTag) { "$commitCount commit(s) since $lastTag" } else { "$commitCount commit(s) — first release" }
                Write-Host "  Tagging $repo ($sinceMsg)..." -ForegroundColor Green
                $releaseArgs = @("release", "create", $Tag, "--repo", "wkcollis1-eng/$repo", "--title", $releaseTitle, "--notes", $releaseNotes)
                if ($DraftRelease) { $releaseArgs += "--draft" }
                & gh @releaseArgs
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  Release failed for $repo (tag may already exist)" -ForegroundColor Yellow
                } else {
                    git -C $repoPath fetch --tags --quiet
                }
            } else {
                $skipMsg = if ($lastTag) { "no new commits since $lastTag" } else { "no commits found" }
                Write-Host "  Skipping $repo ($skipMsg)" -ForegroundColor Yellow
            }
        }
    }

    Step "Pushing all repos"
    & "$PSScriptRoot\push-all-repos.ps1"

    Write-Host ""
    Write-Host ("═" * 50) -ForegroundColor DarkGray
    Write-Host "Phase 2 complete. Monthly update for $monthDisplay finished." -ForegroundColor White
    Write-Host ""
    Write-Host "Reminders:" -ForegroundColor DarkGray
    Write-Host "  - If .py files changed: run .\deploy-to-ha.ps1 then reload HA Shell Commands" -ForegroundColor DarkGray
    Write-Host "  - Check open issues: .\list-issues.ps1 -Remote -Repo Residential-HVAC-Performance-Baseline-" -ForegroundColor DarkGray
}
