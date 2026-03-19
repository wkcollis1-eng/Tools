# tools

PowerShell utility scripts for managing the wkcollis1-eng GitHub repositories and Home Assistant Green deployment from a Windows PC.

**Repos managed:**
- `home-assistant-config`
- `Residential-HVAC-Performance-Baseline-`
- `Lifepo4-Battery-Banks`
- `DIY-LiFePO4-UPS`
- `tools` (this repo)

---

## Quick start

```powershell
cd C:\repos\tools
.\verify-system.ps1      # confirm environment is clean
.\pull-all-repos.ps1     # sync all repos from GitHub
.\status-all-repos.ps1   # review state before starting
```

If `verify-system.ps1` exits with failures, resolve them before proceeding. Warnings (unpushed commits, non-main branch) are informational — the session can continue.

---

## Operational invariants

These rules are non-negotiable. The scripts enforce them where possible; the rest require discipline.

1. **Never commit data that fails HALT-level validation.** `validate-all.ps1` exits 1 on HALT. `monthly-update.ps1` Phase 2 aborts before pushing if validation fails.
2. **Always run `pull-all-repos.ps1` before any session.** Working on stale local state causes merge conflicts.
3. **Run `deploy-to-ha.ps1` after any script file change.** Six HA shell commands depend on the three deployed scripts. A missing deploy breaks them silently until the next automation fires.
4. **`monthly-update.ps1` Phase 2 requires a clean working tree.** The script enforces this — uncommitted changes in any release repo abort the sequence.
5. **Repo list changes go in `repos.ps1` only.** All scripts source it. Never hardcode a repo name in an individual script.

---

## System guarantees

What this toolkit actively enforces — as opposed to what it relies on discipline for:

- **No partial deploys to HA.** `deploy-to-ha.ps1` verifies SHA-256 hashes after every copy and aborts with a hard error if any mismatch is detected. HA shell commands are not reloadable until all copies verify clean.
- **No release tagging on invalid data.** `monthly-update.ps1` Phase 2 runs `validate-all.ps1` before tagging or pushing. A HALT-level failure stops the sequence entirely.
- **No cross-repo drift in repo list.** `repos.ps1` is the single source of truth. All scripts dot-source it — no script carries its own hardcoded repo list.
- **No silent tool failures.** Every script calls `Assert-Environment` from `common.ps1` before doing real work. Missing tools, missing git identity, or unauthenticated `gh` all throw immediately with a clear message.
- **Deterministic issue publishing.** Local issue files carry their own frontmatter (repo, title, labels). `publish-issue.ps1` reads it directly — no manual parameter entry, no copy-paste into the GitHub UI.

Anything outside these guarantees requires discipline rather than enforcement. Use `verify-system.ps1` at the start of any session to confirm the full environment is clean before proceeding.

---

## Failure model

Defines how each type of failure is handled across all scripts. New scripts must conform to this model.

| Failure type | Exit | Examples | Script behavior |
|---|---|---|---|
| **Hard failure** | 1 | Missing tool, git identity not set, HALT validation, deploy hash mismatch, diverged repo | Throws immediately with actionable message. No partial state left. |
| **Soft failure** | 0 | Per-repo git failure in batch pull/push | Logged with color, script continues to remaining repos, summary shown at end. |
| **Warning** | 0 | Non-main branch, unpushed commits, python not installed | Printed in yellow. Session may proceed. |

**Rules for script authors:**
- Hard failures use `throw` or `exit 1` — never silently continue after a hard failure.
- Soft failures accumulate in a `$failures` or `$results` hash and are reported in the summary.
- Warnings never block execution.
- Multi-repo scripts always print a summary at the end regardless of individual outcomes.


---

## Prerequisites

Before using any script, confirm the following are installed and working on your Windows PC.

### Git
```powershell
git --version
```
If not installed: https://git-scm.com/download/win — accept all defaults.

### Python (for pre-commit hooks)
```powershell
python --version
```
Required for `install-precommit-all.ps1`. Python 3.9+ is fine.

### GitHub CLI (`gh`) — required for `create-release.ps1`, `create-issue.ps1`, and `monthly-update.ps1`
```powershell
gh --version
```
If not installed: https://cli.github.com — then authenticate:
```powershell
gh auth login
```
Follow the prompts. Choose HTTPS and authenticate via browser.

### Samba share mounted and accessible
The deploy script writes to `\\homeassistant\config\scripts\`. Confirm the share is reachable before running:
```powershell
Test-Path \\homeassistant\config\scripts
```
Should return `True`. If not, open File Explorer → Map Network Drive and map `\\homeassistant\config` before proceeding.

---

## One-time setup

### 1. Create the tools repo on GitHub

Go to https://github.com/new and create a repo named `tools` under `wkcollis1-eng`. Add a README. Public or private — your choice.

### 2. Create the local repos root and clone everything

Open PowerShell as a regular user (not administrator) and run:

```powershell
mkdir C:\repos
cd C:\repos
git clone https://github.com/wkcollis1-eng/tools.git
```

Then run the clone script to pull the other four repos:
```powershell
cd C:\repos\tools
.\clone-all-repos.ps1
```

This is safe to run again at any time — it skips repos that already exist locally.

### 3. Unblock downloaded scripts

Windows marks files downloaded from the internet as untrusted and blocks them from running regardless of execution policy. Unblock all scripts in the tools repo with one command:

```powershell
cd C:\repos\tools
Get-ChildItem *.ps1 | Unblock-File
```

Run this again any time you download new or updated `.ps1` files into the repo. No output means success.

Also set the PowerShell execution policy to allow local scripts if you haven't already:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 4. (Optional) Add tools to your PowerShell PATH

To run the scripts from any directory without typing the full path:

```powershell
# Add to current session only:
$env:PATH += ";C:\repos\tools"

# To make permanent, add to your PowerShell profile:
notepad $PROFILE
# Add this line at the bottom:
# $env:PATH += ";C:\repos\tools"
```

### 5. Install pre-commit hooks (optional but recommended)

```powershell
cd C:\repos\tools
.\install-precommit-all.ps1
```

This installs pre-commit in every repo. The hooks run automatically on every `git commit` and catch trailing whitespace, YAML errors, oversized files, and Python formatting issues before they reach GitHub.

After installing, update the hook versions to current:
```powershell
cd C:\repos\home-assistant-config
pre-commit autoupdate
git add .pre-commit-config.yaml
git commit -m "chore: update pre-commit hook versions"
# Repeat for each repo, or run autoupdate inside install-precommit-all.ps1
```

> **Note:** Do not rely on the pinned versions in `.pre-commit-config.yaml` — run `pre-commit autoupdate` after initial install and again periodically.

---

## Scripts

### `common.ps1`
Shared environment validation. **Never run directly** — dot-sourced automatically by every script. Defines `Assert-Environment`, which checks for required tools and git identity before any script does real work.

```powershell
# Used inside scripts — not for direct invocation:
. "$PSScriptRoot\common.ps1"
Assert-Environment                          # git + git identity only
Assert-Environment -RequireGh               # + gh CLI authenticated
Assert-Environment -RequirePython           # + python
Assert-Environment -RequireGh -RequirePython  # all three
```

Each script calls the appropriate variant. If git identity is not configured, any script that touches git will throw immediately with the exact commands to fix it.

---

### `verify-system.ps1`
Full environment health check. Run at the start of any session to confirm the system is in a known-good state before doing real work. Exits 1 if any check fails.

```powershell
.\verify-system.ps1
```

Checks performed:

| Check | Pass condition |
|---|---|
| git installed | `git --version` succeeds |
| git identity | `user.name` and `user.email` configured |
| gh installed | `gh --version` succeeds |
| gh authenticated | `gh auth status` exits 0 |
| python installed | `python --version` succeeds |
| All repos cloned | `.git` present in each repo directory |
| All repos on main | No repo on a non-main branch |
| All working trees clean | No uncommitted or unpushed changes |
| HA Samba share reachable | `\\homeassistant\config\scripts` accessible |
| Last deploy timestamp | Read from `DEPLOY_VERSION.txt` on HA share |

Output is color-coded: green for pass, yellow for warnings (session can proceed), red for failures (resolve before continuing).

---

### `repos.ps1`
Single source of truth for the managed repo list. **Not run directly** — dot-sourced by every other script. To add a repo to the toolkit, add one line here; no other script needs to change.

```powershell
# repos.ps1 is sourced automatically — no manual invocation needed
```

To add a new repo: edit `$Repos` and `$RepoUrls` in `repos.ps1`, then run `clone-all-repos.ps1`.

---

### `clone-all-repos.ps1`
Clones all repos defined in `repos.ps1` into `C:\repos\`. Safe to re-run — skips repos that already exist locally.

```powershell
.\clone-all-repos.ps1
```

---

### `pull-all-repos.ps1`
Runs `git pull` in every repo. **Run this at the start of every session** before opening Claude Code. Warns if any repo is not on `main` (does not abort — legitimate branch work is allowed). Prints a color-coded summary on completion.

```powershell
.\pull-all-repos.ps1
```

---

### `status-all-repos.ps1`
Shows current branch, unpushed commit count, and changed files for every repo. Run before committing or pushing.

```powershell
.\status-all-repos.ps1
```

---

### `deploy-to-ha.ps1`
Copies live Python scripts to the HA Green Samba share. **Run after any commit that modifies a script file.** Performs a hard pre-flight check before touching the share (aborts if any source file is missing or the share is unreachable), then verifies SHA-256 hashes after each copy to catch Samba partial writes.

```powershell
.\deploy-to-ha.ps1
```

**Three scripts are deployed to HA Green** — all three must be in the deploy map:

| Local path | HA Green destination | Used by shell command |
|---|---|---|
| `home-assistant-config\scripts\climate_norms_today.py` | `/config/scripts/climate_norms_today.py` | `climate_norms_today` |
| `home-assistant-config\scripts\csv_manager.py` | `/config/scripts/csv_manager.py` | `appenddailycsv`, `appendmonthlycsv`, `rotatedailycsv`, `backup_input_numbers` |
| `home-assistant-config\scripts\setback_csv.py` | `/config/scripts/setback_csv.py` | `appendsetbacklog_1f`, `appendsetbacklog_2f` |

> **Critical:** `csv_manager.py` and `setback_csv.py` are called by six shell commands in `configuration.yaml`. Deploying only `climate_norms_today.py` will leave those commands broken on HA Green without any visible error until the next time they fire.

After deploying, reload in HA:
**Developer Tools → YAML → Reload Shell Commands**

To add a new script in the future, add one line to the `$deployMap` hash table in `deploy-to-ha.ps1` — no other changes needed.

---

### `push-all-repos.ps1`
Runs `git push` in every repo. Warns if any repo is not on `main`. Reports unpushed commit count per repo and prints a summary. Run `status-all-repos.ps1` first to confirm what will go out.

```powershell
.\push-all-repos.ps1
```

---

### `sync-notes.ps1`
Stages, commits, and pushes any text or doc changes in the `tools` repo in one command. Use this for README updates, issue drafts, and any non-code changes. Does nothing if the working tree is already clean.

```powershell
.\sync-notes.ps1                                              # default commit message
.\sync-notes.ps1 -Message "docs: add cooling buildout draft" # custom message
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Message` | No | Commit message. Defaults to `"docs: update notes and issue files"` |

> Note: this only syncs the `tools` repo (README, issue drafts, scripts). For changes across all repos use `push-all-repos.ps1`.

---

### `create-release.ps1`
Creates a tagged GitHub release using the `gh` CLI. Requires `gh` to be installed and authenticated (see Prerequisites).

```powershell
.\create-release.ps1 -Repo home-assistant-config -Tag v2025.06.1 -Title "June 2025 — AC cooling build-out"
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Repo` | Yes | Repo name (not the full URL — just e.g. `home-assistant-config`) |
| `-Tag` | Yes | Semantic version tag. Use CalVer format `YYYY.MM.N` consistent with your existing releases |
| `-Title` | Yes | Release title shown on GitHub |
| `-Notes` | No | Release body text. Defaults to prompting your editor if omitted |
| `-Draft` | No | Switch. Pass `-Draft` to save as draft instead of publishing immediately |

**Example — draft release for review before publishing:**
```powershell
.\create-release.ps1 -Repo Residential-HVAC-Performance-Baseline- -Tag v2025.06.1 -Title "June 2025 monthly update" -Draft
```

---

### `install-precommit-all.ps1`
Installs pre-commit hooks in all managed repos. Run once after initial clone. Also installs `pre-commit` via pip if not present, and automatically runs `pre-commit autoupdate` in each repo so you never depend on stale pinned versions. If autoupdate modifies `.pre-commit-config.yaml`, the script prints the exact `git add` and `git commit` commands needed to save the update.

```powershell
.\install-precommit-all.ps1
```

---

### `.pre-commit-config.yaml`
Hook configuration file. Copy this into each of your four main repos (a one-liner is in the file header). The `tools` repo also carries its own copy.

Hooks included:
- `trailing-whitespace` — removes trailing spaces
- `end-of-file-fixer` — ensures files end with a newline
- `check-yaml` — validates YAML syntax (catches HA config errors before push)
- `check-added-large-files` — blocks accidental commits of files >500 KB (protects against CSVs)
- `ruff` — Python linting with auto-fix
- `ruff-format` — Python formatting (Black-compatible)

---

### `new-issue.ps1`
Creates a new local issue file in `tools\issues\` from the standard template. The filename is derived from the repo and a slug you provide. Edit the file, then publish it with `publish-issue.ps1`.

```powershell
.\new-issue.ps1 -Repo home-assistant-config -Slug "cooling-buildout"
.\new-issue.ps1 -Repo home-assistant-config -Slug "cooling-buildout" -Open   # opens in Notepad immediately
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Repo` | Yes | Exact repo name |
| `-Slug` | Yes | Short kebab-case description, e.g. `cooling-buildout`. Becomes part of the filename |
| `-Open` | No | Switch. Opens the new file in Notepad immediately |

Creates: `issues\ha-config_cooling-buildout.md` (repo prefix is derived automatically).

---

### `publish-issue.ps1`
Reads the YAML frontmatter from a local issue file and creates the GitHub issue via `gh`. No parameters to remember — everything is in the file.

```powershell
.\publish-issue.ps1 issues\ha-config_cooling-buildout.md
.\publish-issue.ps1 issues\ha-config_cooling-buildout.md -OpenInBrowser
```

**Frontmatter format** (required at the top of every issue file):
```yaml
---
repo: home-assistant-config
title: "feat: AC cooling build-out"
labels: enhancement,hvac
---
```

The script validates that `repo` and `title` are present, warns if the body still contains template placeholder comments, and aborts if the repo name is not in `repos.ps1`.

After a successful publish, the script writes `published_url` back into the file's frontmatter:

```yaml
published_url: https://github.com/wkcollis1-eng/home-assistant-config/issues/2
```

This creates a bidirectional trace — the local file records where it was published, and re-running `publish-issue.ps1` on the same file will warn before creating a duplicate.

---

### `list-issues.ps1`
Lists local issue drafts and/or open GitHub issues across all managed repos. Useful for reviewing what's queued locally before publishing, and for checking GitHub for duplicates.

```powershell
.\list-issues.ps1                                        # local drafts only
.\list-issues.ps1 -Remote                                # GitHub open issues, all repos
.\list-issues.ps1 -Remote -Repo home-assistant-config   # one repo only
.\list-issues.ps1 -All                                   # local drafts + GitHub issues side by side
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Repo` | No | Filter to a single repo. Works with all modes |
| `-Remote` | No | Switch. Fetch and display open issues from GitHub via `gh` |
| `-All` | No | Switch. Show both local drafts and GitHub issues |

Remote mode requires `gh` authenticated. Color-coded by repo — same scheme as `status-all-repos.ps1`.

---

### `issues\TEMPLATE.md`
Standard template for new issue files. Copied automatically by `new-issue.ps1` — do not edit directly. Contains frontmatter fields and section headers that match the project's issue style.

---

### `create-issue.ps1`
Opens a GitHub issue in one of the managed repos. Requires `gh` (see Prerequisites).

```powershell
.\create-issue.ps1 -Repo home-assistant-config -Title "Fix DST in climate_norms_today.py"
.\create-issue.ps1 -Repo Residential-HVAC-Performance-Baseline- -Title "Add March 2026 data" -OpenInBrowser
.\create-issue.ps1 -Repo home-assistant-config -Title "Cooling build-out" -BodyFile "C:\repos\tools\issue_body.md"
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Repo` | Yes | Exact repo name (case-sensitive — see valid list in script) |
| `-Title` | Yes | Issue title |
| `-Body` | No | Issue body as an inline string |
| `-BodyFile` | No | Path to a `.md` file to use as the issue body — use this for long issues like build-out plans |
| `-OpenInBrowser` | No | Switch. Opens the new issue URL in your browser immediately |

> **Note:** If neither `-Body` nor `-BodyFile` is provided, `gh` opens your configured editor so you can write the body interactively. `-BodyFile` is the recommended approach for issues that already exist as Markdown documents (e.g. `GITHUB_ISSUE_1_COOLING_BUILDOUT.md`).

---

### `validate-all.ps1`
Runs `validate_month.py` from the `Residential-HVAC-Performance-Baseline-` repo. Validates all months in the CSV history by default, or a specific month. **Exits 1 if any HALT-level check fails** — safe to use as a gate before committing monthly data.

```powershell
.\validate-all.ps1                    # validate all months
.\validate-all.ps1 -Month 2026-03     # validate March 2026 only
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Month` | No | Month to validate. Accepts `YYYY-MM` or `YYYY-MM-01`. Omit to validate all months |

**Checks run (V-HVAC-1 through V-HVAC-8):**
- V-HVAC-1 — Runtime/HDD within ±2σ of trailing 3-month history
- V-HVAC-2 — Heating efficiency within ±15% of 90.3 CCF/1kHDD baseline
- V-HVAC-3 — Space heat CCF / HDD coherence (implied UA ±5% of 480 BTU/hr-°F)
- V-HVAC-4 — Monthly HDD65 vs 5,270 annual normal
- V-HVAC-5 — Zone balance 1F/2F within 45–55% (heating season only)
- V-HVAC-6 — DHW CCF ≤ prior-year same month +5%
- V-HVAC-7 — `daily_temperature.csv` row count = days in month
- V-HVAC-8 — `monthly_hvac_runtime.csv` has exactly 2 rows per month

Output levels: `✅ PASS`, `⚠️ WARN`, `🚩 FLAG`, `🛑 HALT`. HALT stops the exit code at 1; WARN and FLAG are informational and allow the commit to proceed.

---

### `monthly-update.ps1`
Orchestrates the full 1st-of-month data entry workflow as two distinct phases. Requires `gh`.

**Phase 1 — before the Claude Code session:**
Pulls all repos, validates existing data, and creates a work queue issue with a pre-filled checklist.

```powershell
.\monthly-update.ps1 -Month 2026-03 -Phase 1
```

**Phase 2 — after the Claude Code session:**
Validates the newly entered month, tags releases for repos with new commits, and pushes everything.

```powershell
.\monthly-update.ps1 -Month 2026-03 -Phase 2 -Tag v2026.03.1
.\monthly-update.ps1 -Month 2026-03 -Phase 2 -Tag v2026.03.1 -DraftRelease   # review before publishing
.\monthly-update.ps1 -Month 2026-03 -Phase 2 -SkipRelease                    # push without tagging
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Month` | Yes | Month being entered. Accepts `YYYY-MM` or `YYYY-MM-01` |
| `-Phase` | Yes | `1` (pre-session) or `2` (post-session) |
| `-Tag` | Phase 2 | CalVer release tag, e.g. `v2026.03.1`. Required unless `-SkipRelease` |
| `-SkipRelease` | No | Switch. Skip release tagging in Phase 2 (push only) |
| `-DraftRelease` | No | Switch. Create releases as drafts for review before publishing |

Phase 2 is smart about releases — it checks `git rev-list` for each repo and only tags repos that have new commits since their last tag. Repos with no changes are skipped automatically.

---

## Issue workflow

Local issue files let you draft, review, and version-control issues before they hit GitHub — useful for large build-out plans like the cooling infrastructure issue.

```powershell
# 1. Create a new local issue file
.\new-issue.ps1 -Repo home-assistant-config -Slug "filter-runtime-fix" -Open

# 2. Edit the file in tools\issues\ha-config_filter-runtime-fix.md
#    Fill in the title, body sections, and labels in the frontmatter

# 3. Check for duplicates before publishing
.\list-issues.ps1 -All -Repo home-assistant-config

# 4. Publish to GitHub when ready
.\publish-issue.ps1 issues\ha-config_filter-runtime-fix.md -OpenInBrowser

# 5. Commit the issue file to the tools repo for reference
git add issues\
git commit -m "docs: add filter runtime fix issue draft"
git push
```

For large issues (like build-out plans generated in a Claude session), copy the markdown body into a new issue file and set the frontmatter — then `publish-issue.ps1` handles the rest with no copy-paste into the GitHub UI.

---

## Daily workflow

```powershell
# --- Start of session ---
cd C:\repos\tools
.\verify-system.ps1           # full health check — resolve any failures before continuing
.\pull-all-repos.ps1          # sync everything from GitHub
.\status-all-repos.ps1        # confirm clean state before starting

# --- Do your Claude Code session ---
# (Claude Code commits per-repo as it works)

# --- End of session ---
.\status-all-repos.ps1        # confirm what's staged/committed
.\deploy-to-ha.ps1            # ONLY if a script file changed
.\push-all-repos.ps1          # push all repos to GitHub
.\sync-notes.ps1              # push any README or issue draft updates in tools
```

---

## Monthly update workflow

On the 1st of each month after utility bills arrive, `monthly-update.ps1` handles the full sequence:

```powershell
# Before your Claude Code session:
.\monthly-update.ps1 -Month 2026-03 -Phase 1
# (pulls all repos, validates data, opens a work queue issue with checklist)

# Run your Claude Code session to enter bill data and update CSVs

# After your Claude Code session:
.\monthly-update.ps1 -Month 2026-03 -Phase 2 -Tag v2026.03.1
# (validates the new month, tags releases for changed repos, pushes everything)
```

If validation fails in Phase 2 with a HALT, the script stops before tagging or pushing. Fix the data error, then re-run Phase 2.

---

## Claude Code hooks

Hooks are shell commands that Claude Code runs automatically at lifecycle events — before or after tool use, on session start/stop, etc. The most useful application for this repo is running `validate_month.py` automatically every time Claude Code writes a CSV in the `Residential-HVAC-Performance-Baseline-` data directory. This closes the loop without requiring you to remember to run validation manually.

### How hooks work

- **`PostToolUse`** — fires after a tool completes. Output goes back to Claude as context; exit code 1 is a non-blocking warning; exit code 0 is success.
- **Matcher** — filters which tool triggers the hook. Uses pipe syntax: `"Write|Edit|MultiEdit"`. Case-sensitive: `Write` and `Edit` are correct; `write` won't match.
- **Settings file** — project-level hooks go in `.claude/settings.json` in the repo root. User-level hooks go in `~/.claude/settings.json` and apply to every project.

### Setup — validation hook for Residential-HVAC-Performance-Baseline-

This hook runs `validate_month.py` automatically after any write to a CSV file in the `data/` directory. It uses a thin Python wrapper to read the hook's stdin JSON, check the file path, and only run validation when a data CSV is actually being written — not on every file write in the repo.

**Step 1 — Create the hook directory:**
```powershell
mkdir C:\repos\Residential-HVAC-Performance-Baseline-\.claude\hooks
```

**Step 2 — Create the wrapper script:**

Save this as `C:\repos\Residential-HVAC-Performance-Baseline-\.claude\hooks\validate_on_csv_write.py`:

```python
#!/usr/bin/env python3
"""
PostToolUse hook — runs validate_month.py after any CSV write in data/.
Reads tool event JSON from stdin (provided by Claude Code).
Exits 0 (PASS/WARN) or 1 (HALT) to mirror validate_month.py exit codes.
"""
import json
import os
import subprocess
import sys

data = json.load(sys.stdin)
file_path = data.get("tool_input", {}).get("file_path", "")

# Only trigger for CSV files in the data directory
if not (file_path.endswith(".csv") and "data" in file_path):
    sys.exit(0)

# Run validate_month.py from repo root
repo_root = os.environ.get("CLAUDE_PROJECT_DIR", ".")
result = subprocess.run(
    [sys.executable, "Scripts/validate_month.py"],
    cwd=repo_root
)

# Exit code propagates back to Claude Code:
#   0 = PASS/WARN (Claude continues normally)
#   1 = HALT (Claude sees failure output and can stop itself)
sys.exit(result.returncode)
```

**Step 3 — Create the settings file:**

Save this as `C:\repos\Residential-HVAC-Performance-Baseline-\.claude\settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "python .claude/hooks/validate_on_csv_write.py"
          }
        ]
      }
    ]
  }
}
```

**Step 4 — Commit both files:**
```powershell
cd C:\repos\Residential-HVAC-Performance-Baseline-
git add .claude/
git commit -m "chore: add PostToolUse validation hook for data CSV writes"
```

### What this does in practice

During a monthly update Claude Code session, every time Claude writes or edits a file in `data/`, the hook fires. If the file isn't a CSV, the wrapper exits 0 immediately (no overhead). If it is a CSV, `validate_month.py` runs and its full output — `✅ PASS`, `⚠️ WARN`, `🚩 FLAG`, or `🛑 HALT` — appears in the Claude Code session. On a HALT, Claude sees the failure before it moves to the next step, giving it the opportunity to stop and report the issue rather than continuing with bad data.

This means `validate-all.ps1` is still useful for a deliberate pre-push check, but you no longer need to remember to run it during the session — validation is automatic.

### Updating hooks after a pre-commit autoupdate

The `.claude/settings.json` file is independent of `.pre-commit-config.yaml` and does not need updating when you run `pre-commit autoupdate`. They are separate systems.

---

## Extending the toolkit

### Adding a new Python script to deploy
When a new `.py` script is added to `home-assistant-config\scripts\` and referenced by a shell command in `configuration.yaml`, add one entry to the `$deployMap` in `deploy-to-ha.ps1`:

```powershell
$deployMap = @{
    "C:\repos\home-assistant-config\scripts\climate_norms_today.py" = "\\homeassistant\config\scripts\climate_norms_today.py"
    "C:\repos\home-assistant-config\scripts\csv_manager.py"         = "\\homeassistant\config\scripts\csv_manager.py"
    "C:\repos\home-assistant-config\scripts\setback_csv.py"         = "\\homeassistant\config\scripts\setback_csv.py"
    # Add new scripts here:
    "C:\repos\home-assistant-config\scripts\new_script.py"          = "\\homeassistant\config\scripts\new_script.py"
}
```

No other changes are needed.

### Adding a new repo to the toolkit
Edit `repos.ps1` — add the repo name to `$Repos` and its clone URL to `$RepoUrls`. Every script that dot-sources `repos.ps1` will automatically include it. Then run `.\clone-all-repos.ps1` to pull it locally.

---

## Repo structure

```
C:\repos\
├── tools\                          ← this repo
│   ├── README.md
│   ├── repos.ps1                   ← single source of truth for repo list
│   ├── common.ps1                  ← shared Assert-Environment, dot-sourced by all scripts
│   ├── .pre-commit-config.yaml
│   ├── verify-system.ps1
│   ├── clone-all-repos.ps1
│   ├── pull-all-repos.ps1
│   ├── push-all-repos.ps1
│   ├── status-all-repos.ps1
│   ├── sync-notes.ps1
│   ├── deploy-to-ha.ps1
│   ├── install-precommit-all.ps1
│   ├── create-release.ps1
│   ├── create-issue.ps1
│   ├── new-issue.ps1
│   ├── publish-issue.ps1
│   ├── list-issues.ps1
│   ├── validate-all.ps1
│   ├── monthly-update.ps1
│   └── issues\                     ← local issue drafts
│       ├── TEMPLATE.md
│       └── ...
├── home-assistant-config\
├── Residential-HVAC-Performance-Baseline-\
│   ├── .claude\
│   │   ├── settings.json           ← PostToolUse validation hook config
│   │   └── hooks\
│   │       └── validate_on_csv_write.py
│   └── ...
├── Lifepo4-Battery-Banks\
└── DIY-LiFePO4-UPS\
```

---

## Troubleshooting

**Any script throws "Git identity not configured"**
`Assert-Environment` in `common.ps1` checks `git config user.name` and `user.email` before proceeding. Fix with:
```powershell
git config --global user.name "Bill Collis"
git config --global user.email "your@email.com"
```

**Any script throws "gh CLI is not authenticated"**
Run `gh auth login` and complete the browser flow. `Assert-Environment -RequireGh` verifies authentication, not just installation.

**`verify-system.ps1` shows FAIL for HA share**
The Samba share is not mounted. Open File Explorer, navigate to `\\homeassistant\config`, enter HA credentials. Re-run after connecting.

**`verify-system.ps1` shows WARN for unpushed commits**
Not a blocker — the session can proceed. Push when the session is complete with `.\push-all-repos.ps1`.

**`deploy-to-ha.ps1` aborts with "missing source file"**
The script now hard-aborts before touching the share if any source file is missing. Confirm the script is committed and pulled: `.\pull-all-repos.ps1`, then retry.

**`deploy-to-ha.ps1` aborts with "Samba share not accessible"**
The share is not mounted. Open File Explorer, navigate to `\\homeassistant\config`, and enter HA credentials when prompted. Once connected, re-run the script.

**`deploy-to-ha.ps1` reports "HASH MISMATCH"**
The file copied to the share does not match the source — likely a Samba partial write. Re-run `deploy-to-ha.ps1` immediately. Do not reload HA shell commands until the script reports all hashes verified.

**`pull-all-repos.ps1` or `push-all-repos.ps1` warns about a non-main branch**
This is a warning, not an error — the script continues. If the branch is unintentional, `cd C:\repos\<repo>` and `git checkout main` before proceeding. If it is intentional, the warning can be ignored.

**`monthly-update.ps1` Phase 2 aborts with "Uncommitted changes"**
The clean working tree guard fired. Commit or stash the changes in the flagged repo, then re-run Phase 2.

**`pre-commit` blocks a commit with a YAML error**
Fix the YAML in the flagged file, then `git add` the file again and retry the commit. The hook output will show the exact line number.

**`gh` is not recognized**
GitHub CLI is not installed or not on PATH. Install from https://cli.github.com and restart PowerShell.

**`create-release.ps1` fails with "release already exists"**
A tag with that name was already pushed. Either delete the tag on GitHub and re-run, or increment the patch number (e.g. `v2025.06.2`).

**`validate-all.ps1` reports "validate_month.py not found"**
The `Residential-HVAC-Performance-Baseline-` repo hasn't been cloned or pulled. Run `.\pull-all-repos.ps1` first.

**`validate-all.ps1` exits with HALT**
One or more months have data integrity issues — the output will identify which check (V-HVAC-1 through V-HVAC-8) failed and why. Fix the CSV data for the flagged month and re-run before committing. Do not bypass a HALT.

**`monthly-update.ps1` stops at Phase 2 before pushing**
Validation failed with a HALT. Fix the data error in the relevant CSV, commit the fix, then re-run `.\monthly-update.ps1 -Month YYYY-MM -Phase 2 -Tag vYYYY.MM.N`.

**`publish-issue.ps1` fails with "Frontmatter missing repo or title"**
The file is missing the `---` frontmatter block or the fields are malformed. Open the file and confirm the top looks exactly like the template — `---` on its own line, then `repo:`, `title:`, `labels:`, then `---` again.

**`publish-issue.ps1` warns about template placeholders**
The body still contains `<!--` comment text from the template. Either fill in the sections or answer `y` at the prompt to publish anyway (useful for minimal issues).

**`create-issue.ps1` fails silently or creates an empty issue**
If neither `-Body` nor `-BodyFile` is provided and no editor is configured, `gh` may create an issue with an empty body. Set a default editor: `gh config set editor notepad` and re-run.

**Hook doesn't fire when Claude Code writes a CSV**
Confirm `.claude/settings.json` is in the repo root (not a subdirectory). Confirm the matcher is `"Write|Edit|MultiEdit"` with exact casing. Confirm `python` is on your PATH (`python --version` in PowerShell). If Claude Code is writing via `Bash` rather than the `Write` tool, add `Bash` to the matcher: `"Write|Edit|MultiEdit|Bash"`.

**Hook fires but validate_month.py output doesn't appear in the session**
The hook command must write to stdout for Claude Code to capture it. `validate_month.py` uses `print()` which goes to stdout — this is correct. If output is missing, the hook may be exiting before the script runs. Add a `print(f"Hook triggered for: {file_path}")` at the top of the wrapper script temporarily to confirm it's being called.

**`git pull` reports merge conflicts**
Do not force-push. Resolve conflicts manually in the affected file, then `git add` and `git commit`. If Claude Code made the conflicting commit, check CLAUDE.md for the session rules that govern how it handles existing content.
