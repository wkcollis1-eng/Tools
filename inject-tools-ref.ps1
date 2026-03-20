# C:\repos\Tools\inject-tools-ref.ps1
# Adds a CLAUDE_TOOLS.md reference block to each repo's CLAUDE.md.
# Safe to re-run — skips repos where the reference already exists.
# Run once after adding CLAUDE_TOOLS.md to the tools repo.
#
# Usage:
#   .\inject-tools-ref.ps1

. "$PSScriptRoot\common.ps1"
Assert-Environment
. "$PSScriptRoot\repos.ps1"

$toolsRef = @"

## Tools Reference

See `C:\repos\Tools\CLAUDE_TOOLS.md` for the full toolkit contract (ultra-minified, Claude-optimized).
Use CLAUDE_TOOLS.md as the authoritative reference during sessions — read it instead of README.md.

Key commands:
- Session: ``.\session-start.ps1`` / ``.\session-end.ps1``
- Publish issue: ``.\publish-and-sync.ps1 issues\<file>``
- Release: ``.\release.ps1 -Repo X -Tag vY -Title Z``
- Monthly: ``.\monthly-update.ps1 -Month YYYY-MM -Phase 1|2``
"@

$updated = 0
$skipped = 0

foreach ($repo in $Repos) {
    if ($repo -eq "tools") { continue }  # tools repo doesn't need a self-reference

    $claudeMd = "$ReposRoot\$repo\CLAUDE.md"

    if (!(Test-Path $claudeMd)) {
        Write-Host "[$repo] No CLAUDE.md found — skipping" -ForegroundColor Yellow
        $skipped++
        continue
    }

    $content = Get-Content $claudeMd -Raw
    if ($content -match "CLAUDE_TOOLS\.md") {
        Write-Host "[$repo] Already has CLAUDE_TOOLS reference — skipping" -ForegroundColor Gray
        $skipped++
        continue
    }

    # Append at end of file
    $content = $content.TrimEnd() + "`n" + $toolsRef + "`n"
    Set-Content $claudeMd $content -NoNewline
    Write-Host "[$repo] CLAUDE_TOOLS reference added" -ForegroundColor Green
    $updated++
}

Write-Host ""
Write-Host "$updated repo(s) updated, $skipped skipped." -ForegroundColor Cyan
if ($updated -gt 0) {
    Write-Host "Commit and push the CLAUDE.md changes:" -ForegroundColor Yellow
    Write-Host "  .\push-all-repos.ps1" -ForegroundColor Yellow
}
