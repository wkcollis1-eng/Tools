# CLAUDE_TOOLS.md
# Claude Code reference for C:\repos\Tools — read instead of README.md

---

## Task → Script

| Task | Command |
|---|---|
| start | `.\session-start.ps1` |
| end | `.\session-end.ps1` |
| status | `.\status-all-repos.ps1 [-Table]` |
| publish issue | `.\publish-and-sync.ps1 issues\<file>` |
| publish only | `.\publish-issue.ps1 issues\<file>` |
| release | `.\release.ps1 -Repo X -Tag vY -Title Z` |
| create release | `.\create-release.ps1 -Repo X -Tag vY -Title Z` |
| monthly | `.\monthly-update.ps1 -Month YYYY-MM -Phase 1\|2` |
| deploy | `.\deploy-to-ha.ps1` |
| validate | `.\validate-all.ps1 [-Month YYYY-MM]` |
| new issue | `.\new-issue.ps1 -Repo X -Slug Y` |
| create issue | `.\create-issue.ps1 -Repo X -Title Y` |
| list issues | `.\list-issues.ps1 [-Remote] [-All]` |
| verify | `.\verify-system.ps1` |
| pull | `.\pull-all-repos.ps1` |
| push | `.\push-all-repos.ps1` |
| sync docs | `.\sync-notes.ps1` |
| inject tools ref | `.\inject-tools-ref.ps1` |
| add repo | edit `repos.ps1` → `clone-all-repos.ps1` |
| add HA script | edit `$deployMap` in `deploy-to-ha.ps1` |
| bootstrap | `.\bootstrap.ps1` |
| pre-commit hooks | `.\install-precommit-all.ps1 [-UpdateOnly]` |

---

## Scope

Repos: `home-assistant-config` · `Residential-HVAC-Performance-Baseline-` · `Lifepo4-Battery-Banks` · `DIY-LiFePO4-UPS` · `Tools`
Root: `C:\repos\`
**Repo list: `repos.ps1` only**
**Shared infrastructure: `common.ps1`** (dot-sourced by all scripts — never run directly)

---

## Invariants (hard)

* HALT data ⇒ stop (never commit)
* pull before work
* deploy after `.py` change
* Phase 2 ⇒ clean repos
* no repo list duplication

---

## Failure model

| Type | Exit | Behavior |
|---|---|---|
| Hard | 1 | Write-Host Red + exit 1 (no throw) |
| Soft | 0 | log + continue + summarize |
| Warn | 0 | informational |

Rules: no continuation after hard fail · multi-repo ⇒ summary · no silent failure

---

## Workflows

### Daily

```powershell
.\session-start.ps1
# work
.\session-end.ps1
```

Flags: `-Deploy` · `-NoDeploy` · `-NoSync`

### Monthly

```powershell
.\monthly-update.ps1 -Month YYYY-MM -Phase 1
.\monthly-update.ps1 -Month YYYY-MM -Phase 2 -Tag vYYYY.MM.N
```

HALT ⇒ fix → rerun Phase 2
Only changed repos released

---

## Issues

```powershell
.\new-issue.ps1 -Repo X -Slug Y
.\publish-and-sync.ps1 issues\<file>
```

Frontmatter: `repo` · `title` · `labels`
`published_url` auto-written on publish; re-run warns

---

## Deploy (HA)

Target: `\\homeassistant\config\scripts\`

| Script | Shell commands |
|---|---|
| `climate_norms_today.py` | `climate_norms_today` |
| `csv_manager.py` | `appenddailycsv` · `appendmonthlycsv` · `rotatedailycsv` · `backup_input_numbers` |
| `setback_csv.py` | `appendsetbacklog_1f` · `appendsetbacklog_2f` |

Failures ⇒ abort: missing file · share unreachable · hash mismatch
Post: write `DEPLOY_VERSION.txt` (timestamp + commit hash) · HA → Reload Shell Commands

---

## Validation (V-HVAC)

Statistical + structural checks. HALT = structural (row counts).

Levels: PASS · WARN · FLAG · HALT
Only HALT blocks

---

## Claude hook

`PostToolUse: Write|Edit|MultiEdit`
If `data/*.csv` ⇒ run validation
HALT surfaces immediately

---

## Environment

All scripts dot-source `common.ps1` and call `Assert-Environment` before doing real work:

```powershell
Assert-Environment [-RequireGh] [-RequirePython] [-RequirePreCommit] [-RequireSamba]
```

Checks: git 2.x + identity · gh + auth · python 3.x (PYTHONUTF8=1 for validation) · pre-commit module · Samba share
Shared functions: `Test-GitRepo $path` · `Get-Frontmatter $file`
Shared constants: `$SambaSharePath`

---

## Guarantees

* atomic HA deploy (hash-verified)
* no invalid releases (validation-gated)
* no repo drift (`repos.ps1`)
* no silent failure (env enforced)
* deterministic issues (frontmatter)
* deploy traceable (commit → HA)

---

## Rules

**Pull → Work → Validate → Deploy → Push**

Never: bypass HALT · push before deploy · duplicate repo list · allow silent failure

---

## Troubleshooting

| Issue | Action |
|---|---|
| HALT | fix data |
| deploy fail | fix share / rerun |
| start fail | fix `verify-system` |
| gh auth | `gh auth login` |
| git identity | set global config |
| dirty Phase 2 | commit/stash |
| hook fail | check matcher/python/path |
| push reject | pull + resolve |
