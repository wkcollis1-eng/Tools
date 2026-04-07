# C:\repos\Tools\verify-system.ps1
# Full environment health check. Run at the start of any session.
#
# Usage:
#   .\verify-system.ps1           # standard check (with git fetch per repo)
#   .\verify-system.ps1 -NoFetch  # skip fetch (faster, offline-safe)
#   .\verify-system.ps1 -Json     # export results to verify-results.json

param(
    [switch]$NoFetch,
    [switch]$Json
)

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\repos.ps1"

$verificationResults = [System.Collections.Generic.List[hashtable]]::new()

function Add-Result([string]$category, [string]$item, [string]$status, [string]$message, [string]$details = "") {
    $script:verificationResults.Add(@{
        Category  = $category
        Item      = $item
        Status    = $status
        Message   = $message
        Details   = $details
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    })
}

$pass = 0; $warn = 0; $fail = 0

function Ok([string]$msg)   { Write-Host "  OK    $msg" -ForegroundColor Green;  $script:pass++ }
function Warn([string]$msg) { Write-Host "  WARN  $msg" -ForegroundColor Yellow; $script:warn++ }
function Fail([string]$msg) { Write-Host "  FAIL  $msg" -ForegroundColor Red;    $script:fail++ }

Write-Host ""
Write-Host "System Verification  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host ("-" * 50) -ForegroundColor DarkGray

# -- Tools ---------------------------------------------------------------------
Write-Host ""
Write-Host "TOOLS" -ForegroundColor White

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVersion = (git --version 2>$null).Trim()
    $gitName    = (git config user.name  2>$null)
    $gitEmail   = (git config user.email 2>$null)
    if ($gitName -and $gitEmail) {
        Ok "git -- $gitVersion ($gitName <$gitEmail>)"
        Add-Result "Tools" "git" "OK" "$gitVersion ($gitName <$gitEmail>)"
    } else {
        Fail "git installed but identity not configured (run: git config --global user.name / user.email)"
        Add-Result "Tools" "git" "FAIL" "Identity not configured"
    }
} else {
    Fail "git not found -- https://git-scm.com/download/win"
    Add-Result "Tools" "git" "FAIL" "Not found"
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $null = gh auth status 2>$null
    if ($LASTEXITCODE -eq 0) {
        $ghVersion = (gh --version 2>$null | Select-Object -First 1).Trim()
        Ok "gh  -- $ghVersion"
        Add-Result "Tools" "gh" "OK" $ghVersion
    } else {
        Fail "gh installed but not authenticated (run: gh auth login)"
        Add-Result "Tools" "gh" "FAIL" "Not authenticated"
    }
} else {
    Fail "gh not found -- https://cli.github.com"
    Add-Result "Tools" "gh" "FAIL" "Not found"
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    $pyVersion = (python --version 2>$null).Trim()
    Ok "python -- $pyVersion"
    Add-Result "Tools" "python" "OK" $pyVersion
} else {
    Warn "python not found (required for validate-all, install-precommit-all, monthly-update)"
    Add-Result "Tools" "python" "WARN" "Not found"
}

# -- Repos ---------------------------------------------------------------------
Write-Host ""
Write-Host "REPOS" -ForegroundColor White

foreach ($repo in $Repos) {
    $path = $RepoMap[$repo].Path

    if (!(Test-GitRepo $path)) {
        Fail "$repo -- not cloned (run: .\clone-all-repos.ps1)"
        Add-Result "Repos" $repo "FAIL" "Not cloned"
        continue
    }

    $branch = (git -C $path rev-parse --abbrev-ref HEAD 2>$null).Trim()
    $dirty  = git -C $path status --porcelain 2>$null

    if (!$NoFetch) {
        git -C $path fetch origin --quiet 2>$null
    }

    # Divergence detection -- guards against repos with no remote tracking branch.
    # Detects the actual default branch name (main, master, or other) rather than
    # assuming 'main' -- avoids silently showing 0 ahead/behind on repos using 'master'.
    $ahead      = 0
    $behind     = 0
    $defaultBranch = (git -C $path symbolic-ref "refs/remotes/origin/HEAD" 2>$null)
    if ($defaultBranch) {
        $defaultBranch = $defaultBranch.Trim() -replace '^refs/remotes/origin/', ''
    }

    if ($defaultBranch) {
        $null = git -C $path rev-parse --verify "origin/$defaultBranch" 2>$null
        if ($LASTEXITCODE -eq 0) {
            # FIX: trim trailing newline before regex -- without Trim() the regex
            # "^(\d+)\s+(\d+)$" does not match and $ahead/$behind stay 0,
            # silently missing repos that are ahead or behind origin.
            $divRaw = (git -C $path rev-list --left-right --count "origin/$defaultBranch...HEAD" 2>$null |
                       Out-String).Trim()
            if ($divRaw -match "^(\d+)\s+(\d+)$") {
                $behind = [int]$Matches[1]
                $ahead  = [int]$Matches[2]
            }
        }
    }

    $preCommitConfig  = Test-Path (Join-Path $path ".pre-commit-config.yaml")
    $preCommitHook    = Test-Path (Join-Path $path ".git\hooks\pre-commit")

    # Use the detected default branch for the check -- avoids false WARN on repos
    # whose default branch is 'master' or something other than 'main'.
    $expectedBranch = if ($defaultBranch) { $defaultBranch } else { "main" }
    if ($branch -ne $expectedBranch) {
        Warn "$repo -- on branch '$branch' (expected $expectedBranch)"
        Add-Result "Repos" $repo "WARN" "Wrong branch" "On '$branch', expected '$expectedBranch'"
    } elseif ($dirty) {
        $count = ($dirty -split "`n" | Where-Object { $_ }).Count
        Fail "$repo -- $count uncommitted change(s)"
        Add-Result "Repos" $repo "FAIL" "Dirty working tree" "$count uncommitted changes"
    } elseif ($behind -gt 0 -and $ahead -gt 0) {
        Fail "$repo -- DIVERGED ($ahead ahead, $behind behind origin/$defaultBranch)"
        Add-Result "Repos" $repo "FAIL" "Diverged" "$ahead ahead, $behind behind"
    } elseif ($behind -gt 0) {
        Fail "$repo -- $behind commit(s) behind origin/$defaultBranch (run: git pull)"
        Add-Result "Repos" $repo "FAIL" "Behind remote" "$behind behind"
    } elseif ($ahead -gt 0) {
        Warn "$repo -- $ahead unpushed commit(s)"
        Add-Result "Repos" $repo "WARN" "Unpushed commits" "$ahead unpushed"
    } elseif (!$preCommitConfig) {
        Warn "$repo -- no .pre-commit-config.yaml (run: .\install-precommit-all.ps1)"
        Add-Result "Repos" $repo "WARN" "No pre-commit config"
    } elseif (!$preCommitHook) {
        Warn "$repo -- pre-commit hook not installed (run: .\install-precommit-all.ps1)"
        Add-Result "Repos" $repo "WARN" "Hook not installed"
    } else {
        Ok "$repo -- clean, on $expectedBranch, in sync"
        Add-Result "Repos" $repo "OK" "Healthy"
    }
}

# -- HA Green ------------------------------------------------------------------
Write-Host ""
Write-Host "HA GREEN" -ForegroundColor White

$deployedScripts = @("climate_norms_today.py", "csv_manager.py", "setback_csv.py")
$missingScripts  = @()

if (Test-Path $SambaSharePath) {
    # Write-access probe
    $testFile = Join-Path $SambaSharePath ".verify_$(Get-Random).tmp"
    $writable = $false
    try {
        "test" | Set-Content $testFile -ErrorAction Stop
        Remove-Item $testFile -ErrorAction Stop
        $writable = $true
    } catch {
        # Share is reachable but read-only -- not an error, just report WARN below
        $writable = $false
        Write-Verbose "Samba write probe failed: $_"
    }

    # Deployed scripts present?
    $missingScripts = $deployedScripts | Where-Object { !(Test-Path (Join-Path $SambaSharePath $_)) }

    # Last deploy record
    $versionFile = Join-Path $SambaSharePath "DEPLOY_VERSION.txt"
    $lastDeploy  = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "(no deploy record)" }

    if ($writable) {
        Ok "Samba share reachable and writable"
        Add-Result "HA Green" "Samba Share" "OK" "Accessible and writable" $lastDeploy
    } else {
        Warn "Samba share reachable but read-only"
        Add-Result "HA Green" "Samba Share" "WARN" "Read-only" $lastDeploy
    }
    Write-Host "         Last deploy: $lastDeploy" -ForegroundColor DarkGray

    if ($missingScripts.Count -eq 0) {
        Ok "All deployed scripts present ($($deployedScripts -join ', '))"
        Add-Result "HA Green" "Deployed Scripts" "OK" "All present"
    } else {
        Warn "Missing deployed scripts: $($missingScripts -join ', ')"
        Add-Result "HA Green" "Deployed Scripts" "WARN" "Missing scripts" ($missingScripts -join ', ')
    }
} else {
    Fail "Samba share not reachable: $SambaSharePath"
    Add-Result "HA Green" "Samba Share" "FAIL" "Not reachable"
}

# -- Summary -------------------------------------------------------------------
Write-Host ""
Write-Host ("-" * 50) -ForegroundColor DarkGray

$total = $pass + $warn + $fail   # FIX: $total was computed but not used in RESULT line

if ($Json) {
    $jsonOutput = @{
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        NoFetch   = $NoFetch.IsPresent
        Summary   = @{ Passed = $pass; Warnings = $warn; Failed = $fail; Total = $total }
        Results   = $verificationResults
    }
    $outFile = Join-Path $PSScriptRoot "verify-results.json"
    $jsonOutput | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8
    Write-Host "JSON results written to: $outFile" -ForegroundColor DarkGray
}

if ($fail -gt 0) {
    Write-Host "RESULT: $fail failure(s), $warn warning(s), $pass passed of $total -- resolve failures before proceeding" -ForegroundColor Red
    exit 1
} elseif ($warn -gt 0) {
    Write-Host "RESULT: $warn warning(s), $pass passed of $total -- review warnings before session" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "RESULT: All $total checks passed -- system ready" -ForegroundColor Green
    exit 0
}
