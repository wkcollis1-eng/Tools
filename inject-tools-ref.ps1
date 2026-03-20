# C:\repos\Tools\inject-tools-ref.ps1
# Adds a CLAUDE_TOOLS.md reference block to each repo's CLAUDE.md.
# Safe to re-run — skips repos where the reference already exists.
# Run once after adding CLAUDE_TOOLS.md to the Tools repo.
#
# Usage:
#   .\inject-tools-ref.ps1

. "$PSScriptRoot\common.ps1"
Assert-Environment
. "$PSScriptRoot\repos.ps1"

# Reference block appended to each CLAUDE.md.
# Uses $ReposRoot so it adapts to -ReposRoot overrides in bootstrap.
$toolsRef = @"

## Tools Reference

See ``$ReposRoot\Tools\CLAUDE_TOOLS.md`` for the full toolkit contract (ultra-minified, Claude-optimized).
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
    # "Tools" is the correct casing — skip self-reference
    if ($repo -eq "Tools") { continue }

    $claudeMd = "$ReposRoot\$repo\CLAUDE.md"

    if (!(Test-Path $claudeMd)) {
        Write-Host "[$repo] No CLAUDE.md found — skipping" -ForegroundColor Yellow
        $skipped++
        continue
    }

    $content = Get-Content $claudeMd -Raw -Encoding UTF8
    if ($content -match "CLAUDE_TOOLS\.md") {
        Write-Host "[$repo] Already has CLAUDE_TOOLS reference — skipping" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    # Append reference block with a guaranteed trailing newline.
    # Do NOT use -NoNewline: the pre-commit end-of-file-fixer hook will create
    # a spurious diff on every subsequent commit if the file lacks a final newline.
    $newContent = $content.TrimEnd() + "`n" + $toolsRef.TrimEnd() + "`n"
    Set-Content $claudeMd $newContent -Encoding UTF8

    Write-Host "[$repo] CLAUDE_TOOLS reference added" -ForegroundColor Green
    $updated++
}

Write-Host ""
Write-Host "$updated repo(s) updated, $skipped skipped." -ForegroundColor Cyan
if ($updated -gt 0) {
    Write-Host "Commit and push the CLAUDE.md changes:" -ForegroundColor Yellow
    Write-Host "  .\push-all-repos.ps1" -ForegroundColor Yellow
}
