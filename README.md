# tools

PowerShell utility scripts for managing the wkcollis1-eng GitHub repositories and Home Assistant Green deployment from a Windows PC.

**Repos managed:**
- `home-assistant-config`
- `Residential-HVAC-Performance-Baseline-`
- `Lifepo4-Battery-Banks`
- `DIY-LiFePO4-UPS`
- `Tools` (this repo)

---

## Quick start

```powershell
cd C:\repos\Tools
.\session-start.ps1   # verify, pull, status — all in one
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
- Hard failures use `exit 1` with a `Write-Host` error message — never `throw` in scripts called by parents (throw produces noisy or swallowed output when called from a pipeline). Reserve `throw` for strict-mode guard clauses at the top of standalone scripts only.
- Soft failures accumulate in a `$failures` or `$results` hash and are reported in the summary.
- Warnings never block execution.
- Multi-repo scripts always print a summary at the end regardless of individual outcomes.


---

## Claude Code integration

`CLAUDE_TOOLS.md` is an ultra-minified version of this README optimized for Claude Code sessions. It covers all contracts, workflows, scripts, and failure modes in ~150 lines instead of ~900 — reducing token consumption per lookup by ~85%.

**Setup (one-time):**

```powershell
# 1. Copy CLAUDE_TOOLS.md to the tools repo (already done if you pulled recently)
# 2. Inject a reference into each repo's CLAUDE.md:
cd C:\repos\Tools
.\inject-tools-ref.ps1
.\push-all-repos.ps1
```

**How Claude Code uses it:**

During any session, Claude Code reads `CLAUDE_TOOLS.md` as the authoritative reference instead of `README.md`. The Task → Script mapping table at the top lets it pattern-match directly from your request to the correct command without reading through documentation. The contracts section ensures it enforces the same invariants and failure model the scripts enforce.

`README.md` remains the human-readable reference for setup, detailed parameters, and troubleshooting.

---

## Prerequisites

Before using any script, confirm the following are installed and working on your Windows PC.

### Git (2.x required)
```powershell
git --version
```
If not installed: https://git-scm.com/download/win — accept all defaults. Git 2.x is the minimum; `Assert-Environment` will throw with the version it detected if the requirement is not met.

### Python 3.x (for pre-commit hooks)
```powershell
python --version
```
Required for `install-precommit-all.ps1`. Python 3.x is required — `Assert-Environment -RequirePython` checks the major version and throws if it is not 3.

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

### 1. Run bootstrap.ps1 (new machine setup)

On a fresh Windows machine, download `bootstrap.ps1` from the repo and run it. It handles everything in steps 2–5 automatically:

```powershell
# After installing git, python, and gh (see Prerequisites):
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
cd <directory where you downloaded bootstrap.ps1>
Unblock-File .\bootstrap.ps1
.\bootstrap.ps1                          # standard — clones to C:\repos
.\bootstrap.ps1 -ReposRoot D:\repos      # custom repos root
.\bootstrap.ps1 -SkipPrecommit           # skip pre-commit install step
```

Bootstrap handles: git 2.x and Python 3.x version checks, gh authentication, git identity, execution policy, cloning all repos, unblocking scripts, installing pre-commit hooks, and running `verify-system.ps1` automatically at the end. It writes a `bootstrap.log` in the script directory for post-run review. Skip to Step 6 if bootstrap completed successfully.

---

### 2. Create the tools repo on GitHub (first time only)

Go to https://github.com/new and create a repo named `tools` under `wkcollis1-eng`. Add a README. Public or private — your choice.

### 2. Create the local repos root and clone everything

Open PowerShell as a regular user (not administrator) and run:

```powershell
mkdir C:\repos
cd C:\repos
git clone https://github.com/wkcollis1-eng/Tools.git
```

Then run the clone script to pull the other four repos:
```powershell
cd C:\repos\Tools
.\clone-all-repos.ps1
```

This is safe to run again at any time — it skips repos that already exist locally.

### 3. Unblock downloaded scripts

Windows marks files downloaded from the internet as untrusted and blocks them from running regardless of execution policy. Unblock all scripts in the tools repo with one command:

```powershell
cd C:\repos\Tools
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
$env:PATH += ";C:\repos\Tools"

# To make permanent, add to your PowerShell profile:
notepad $PROFILE
# Add this line at the bottom:
# $env:PATH += ";C:\repos\Tools"
```

### 5. Install pre-commit hooks (optional but recommended)

```powershell
cd C:\repos\Tools
.\install-precommit-all.ps1
```

This installs pre-commit in every repo. The hooks run automatically on every `git commit` and catch trailing whitespace, YAML errors, oversized files, and Python formatting issues before they reach GitHub.

After installing, update the hook versions to current:
```powershell
cd C:\repos\home-assistant-config
python -m pre_commit autoupdate
git add .pre-commit-config.yaml
git commit -m "chore: update pre-commit hook versions"
# Repeat for each repo, or run autoupdate inside install-precommit-all.ps1
```

> **Note:** Always use `python -m pre_commit` rather than the `pre-commit` binary directly. On Windows, a freshly pip-installed `pre-commit` binary may not appear on PATH in the same PowerShell session. The module invocation always works.

---

## Scripts

### `common.ps1`
Shared environment validation. **Never run directly** — dot-sourced automatically by every script. Defines `Assert-Environment`, which checks for required tools and git identity before any script does real work. Also exports the `$SambaSharePath` constant (`\\homeassistant\config\scripts`) used by `deploy-to-ha.ps1` and `verify-system.ps1`.

```powershell
# Used inside scripts — not for direct invocation:
. "$PSScriptRoot\common.ps1"
Assert-Environment                                             # git 2.x + git identity
Assert-Environment -RequireGh                                  # + gh CLI authenticated
Assert-Environment -RequirePython                              # + python 3.x
Assert-Environment -RequireGh -RequirePython                   # all three
Assert-Environment -RequirePython -RequirePreCommit            # + python -m pre_commit available
Assert-Environment -RequirePython -RequireSamba                # + Samba share reachable
```

Each script calls the appropriate variant. If git identity is not configured, any script that touches git will throw immediately with the exact commands to fix it. `-RequirePreCommit` uses `python -m pre_commit` (not the binary) to avoid the Windows PATH-not-updated-after-pip-install problem. `-RequireSamba` calls `Test-Path $SambaSharePath` and throws if the share is not mounted.

---

### `session-start.ps1`
Single command to begin any work session. Runs `verify-system.ps1`, `pull-all-repos.ps1`, and `status-all-repos.ps1` in sequence. Aborts on any hard failure — if the environment is not clean, the session does not start.

```powershell
.\session-start.ps1           # Normal startup (pulls all repos)
.\session-start.ps1 -NoPull  # Skip pull step (offline or air-gapped work)
```

| Parameter | Description |
|---|---|
| `-NoPull` | Skip the pull step entirely — useful when working offline or on a local branch with no remote changes expected |

---

### `session-end.ps1`
Single command to close any work session. Shows repo status, prompts for HA deploy if needed (auto-detects `.py` and `.yaml` changes in `home-assistant-config`), pushes all repos, and syncs notes.

```powershell
.\session-end.ps1              # prompts whether to deploy
.\session-end.ps1 -Deploy      # always deploy (skips prompt)
.\session-end.ps1 -NoDeploy    # skip deploy entirely
.\session-end.ps1 -NoSync      # skip sync-notes
```

**Parameters:**

| Parameter | Description |
|---|---|
| `-Deploy` | Always run `deploy-to-ha.ps1` without prompting |
| `-NoDeploy` | Skip deploy step entirely |
| `-NoSync` | Skip `sync-notes.ps1` (no doc changes this session) |

The deploy prompt is context-aware: if `session-end.ps1` detects `.py` or `.yaml` file changes in `home-assistant-config` across all unpushed commits (using `@{u}..HEAD`), it defaults to **Y** for `.py` changes. If `.yaml` changes are detected, a reminder to reload the affected HA domain is shown before the prompt. Pass `-Deploy` or `-NoDeploy` to skip the prompt entirely.

If deploy fails, the session end aborts before pushing — preventing a push that references scripts not yet deployed to HA.

---

### `publish-and-sync.ps1`
Full issue publishing workflow in one command: checks for GitHub duplicates, publishes the issue, then commits the updated file (with `published_url` written back) to the tools repo.

```powershell
.\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md
.\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md -OpenInBrowser
.\publish-and-sync.ps1 issues\ha-config_cooling-buildout.md -SkipDuplicateCheck
```

**Parameters:**

| Parameter | Description |
|---|---|
| `-OpenInBrowser` | Open the new issue URL in your browser after publishing |
| `-SkipDuplicateCheck` | Skip the `list-issues.ps1 -Remote` step |

Replaces the three-step manual sequence: `list-issues.ps1 -All`, `publish-issue.ps1`, `sync-notes.ps1`.

---

### `release.ps1`
Creates a tagged GitHub release with an automatic validation gate for the HVAC baseline repo. For `Residential-HVAC-Performance-Baseline-`, runs `validate-all.ps1` before tagging — a HALT stops the release. For all other repos, tags immediately. Validates CalVer tag format before proceeding. Fetches tags locally after creation so `git describe` is immediately accurate. Auto-generates release notes from `git log --oneline` since the last tag if `-Notes` is omitted.

```powershell
.\release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026 — cooling build-out"
.\release.ps1 -Repo Residential-HVAC-Performance-Baseline- -Tag v2026.03.1 -Title "March 2026" -Month 2026-03
.\release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026" -Draft
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Repo` | Yes | Repo name |
| `-Tag` | Yes | CalVer tag — must match `vYYYY.MM.N` (e.g. `v2026.03.1`). Script rejects malformed tags before any GitHub call |
| `-Title` | Yes | Release title |
| `-Month` | HVAC repo | Month to validate, e.g. `2026-03`. Required for HVAC repo to scope validation |
| `-Notes` | No | Release body text. Auto-generated from `git log --oneline` since last tag if omitted |
| `-Draft` | No | Create as draft for review before publishing |
| `-SkipValidation` | No | Skip validation even for HVAC repo (use with caution) |

---

### `bootstrap.ps1`
Full first-time setup from a fresh Windows machine. Checks prerequisites (including git 2.x and Python 3.x version minimums), authenticates gh, configures git identity, sets execution policy, clones all repos, unblocks scripts, installs pre-commit hooks, and runs `verify-system.ps1` automatically at the end. Writes `bootstrap.log` in the script directory for post-run review.

```powershell
# On a fresh machine after installing git, python, and gh:
Unblock-File .\bootstrap.ps1
.\bootstrap.ps1                          # standard — clones to C:\repos
.\bootstrap.ps1 -ReposRoot D:\repos      # custom repos root
.\bootstrap.ps1 -SkipPrecommit           # skip pre-commit install step
```

| Parameter | Required | Description |
|---|---|---|
| `-ReposRoot` | No | Root directory for all repos. Defaults to `C:\repos` |
| `-SkipPrecommit` | No | Skip the pre-commit install step (useful on machines without pip access) |

This is the only script that can be run before the toolkit is set up — it has no dependency on `common.ps1` or `repos.ps1` being present. Both are dot-sourced automatically once the Tools repo is cloned. All steps are safe to re-run — completed steps are skipped.

---

### `inject-tools-ref.ps1`
Adds a `CLAUDE_TOOLS.md` reference block to each repo's `CLAUDE.md`. Safe to re-run — skips repos where the reference already exists. Run once after initial setup.

```powershell
.\inject-tools-ref.ps1
.\push-all-repos.ps1    # commit the CLAUDE.md updates
```

---

### `verify-system.ps1`
Full environment health check. Run at the start of any session to confirm the system is in a known-good state before doing real work. Exits 1 if any check fails.

```powershell
.\verify-system.ps1              # Standard health check
.\verify-system.ps1 -NoFetch    # Skip git fetch (faster, offline-safe)
.\verify-system.ps1 -Json       # Export results to verify-results.json
```

| Parameter | Description |
|---|---|
| `-NoFetch` | Skip `git fetch origin` per repo — avoids network calls when offline or when divergence data is not needed |
| `-Json` | Export all check results to `verify-results.json` in the Tools repo root |

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
| Repo divergence | `origin/main` exists and is not diverged (guarded — skipped if no remote tracking branch) |
| Pre-commit hooks installed | `.git/hooks/pre-commit` present per repo |
| HA Samba share reachable | `\\homeassistant\config\scripts` accessible |
| HA Samba share writable | Probe file write succeeds on share |
| Deployed scripts present | Expected `.py` files exist on share |
| Last deploy timestamp | Read from `DEPLOY_VERSION.txt` on HA share |

Output is color-coded: green for pass, yellow for warnings (session can proceed), red for failures (resolve before continuing).

---

### `repos.ps1`
Single source of truth for the managed repo list. **Not run directly** — dot-sourced by every other script. To add a repo to the toolkit, add one line here; no other script needs to change.

```powershell
# repos.ps1 is sourced automatically — no manual invocation needed
```

To add a new repo: edit `$Repos` and `$RepoUrls` in `repos.ps1`, then run `clone-all-repos.ps1`. The unified `$RepoMap` hash (keyed by repo name, with `.Path` and `.Url` properties) is rebuilt automatically — scripts use `$RepoMap[$repo].Path` instead of constructing paths manually.

`$ReposRoot` defaults to `C:\repos` and can be overridden by setting `$env:REPOS_ROOT` before dot-sourcing:
```powershell
$env:REPOS_ROOT = "D:\repos"
. "$PSScriptRoot\repos.ps1"
```

---

### `clone-all-repos.ps1`
Clones all repos defined in `repos.ps1` into `C:\repos\`. Safe to re-run — skips repos that already exist locally (checks for a `.git` subdirectory, not just the directory). Shows a progress bar during cloning. After each successful clone, automatically unblocks all `.ps1` files in the cloned repo so they can run without execution policy prompts. Exits 1 if any clone fails.

```powershell
.\clone-all-repos.ps1            # standard full clone
.\clone-all-repos.ps1 -Shallow  # --depth 1 shallow clone (faster, less history)
```

| Parameter | Description |
|---|---|
| `-Shallow` | Pass `--depth 1` to git clone — useful on slow connections or when full history is not needed |

---

### `pull-all-repos.ps1`
Runs `git pull --ff-only` in every repo. **Run this at the start of every session** before opening Claude Code. Uses `--ff-only` to surface diverged branches instead of silently creating merge commits. Warns if any repo is not on `main` (does not abort — legitimate branch work is allowed). Shows diff stats for updated repos. Exits 1 if any repo fails; exits 0 if all repos succeed (updated or already up to date).

```powershell
.\pull-all-repos.ps1
```

---

### `status-all-repos.ps1`
Shows current branch, last commit hash and subject, unpushed commit count, and changed files for every repo. Run before committing or pushing.

```powershell
.\status-all-repos.ps1           # Full per-repo display
.\status-all-repos.ps1 -Table   # Compact formatted table
```

| Parameter | Description |
|---|---|
| `-Table` | Output a compact `Format-Table` view with one row per repo — useful for a quick glance at all repo states |

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
Stages, commits, and pushes `README.md` and `issues\` changes in the `Tools` repo in one command. Use this for README updates and issue drafts. **Deliberately scoped** — `.ps1` scripts and other files are never staged by this command (those belong in a proper code commit). Does nothing if neither `README.md` nor `issues\` has changes.

```powershell
.\sync-notes.ps1                                              # auto-generates commit message from changed files
.\sync-notes.ps1 -Message "docs: add cooling buildout draft" # custom message
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Message` | No | Commit message. Auto-generated from changed files if omitted (e.g. `"docs: update issue draft (ha-config_sensor-fix.md)"`) |

> Note: this only syncs `README.md` and `issues\` in the `Tools` repo. For code changes or changes across all repos use `push-all-repos.ps1`.

---

### `create-release.ps1`
Creates a tagged GitHub release using the `gh` CLI. Validates CalVer tag format before proceeding, auto-generates release notes from `git log --oneline` since the last tag if `-Notes` is omitted, and fetches the new tag back locally after creation so `git describe` is immediately accurate. Warns if used on the HVAC baseline repo and prompts for confirmation (recommending `release.ps1` instead for its HALT validation gate).

```powershell
.\create-release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026 — cooling build-out"
.\create-release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026" -Draft
.\create-release.ps1 -Repo home-assistant-config -Tag v2026.03.1 -Title "March 2026" -Notes "Custom notes here"
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Repo` | Yes | Repo name (not the full URL — just e.g. `home-assistant-config`) |
| `-Tag` | Yes | CalVer tag — must match `vYYYY.MM.N` (e.g. `v2026.03.1`). Script rejects malformed tags before any GitHub call |
| `-Title` | Yes | Release title shown on GitHub |
| `-Notes` | No | Release body text. Auto-generated from `git log --oneline` since last tag if omitted |
| `-Draft` | No | Switch. Pass `-Draft` to save as draft instead of publishing immediately |

**Example — draft release for review before publishing:**
```powershell
.\create-release.ps1 -Repo Residential-HVAC-Performance-Baseline- -Tag v2026.03.1 -Title "March 2026 monthly update" -Draft
```

---

### `install-precommit-all.ps1`
Installs pre-commit hooks in all managed repos. Run once after initial clone. Installs `pre-commit` via `pip install --user` if not present, then runs `python -m pre_commit autoupdate` in each repo so you never depend on stale pinned versions. After install, runs `python -m pre_commit run --all-files` to confirm hooks execute correctly. If autoupdate modifies `.pre-commit-config.yaml`, the script prints the exact `git add` and `git commit` commands needed to save the update.

> **Note:** All pre-commit calls use `python -m pre_commit` (not the `pre-commit` binary). On Windows, a freshly pip-installed `pre-commit` binary may not appear on PATH in the same PowerShell session. The module invocation always works.

```powershell
.\install-precommit-all.ps1              # install hooks + autoupdate
.\install-precommit-all.ps1 -UpdateOnly  # autoupdate only, skip install
```

| Parameter | Description |
|---|---|
| `-UpdateOnly` | Skip `pre-commit install` and only run `autoupdate` — useful on re-runs when hooks are already installed |

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
Creates a new local issue file in `Tools\issues\` from the standard template. The filename is derived from the repo and a slug you provide. Edit the file, then publish it with `publish-issue.ps1`.

```powershell
.\new-issue.ps1 -Repo home-assistant-config -Slug "cooling-buildout"
.\new-issue.ps1 -Repo home-assistant-config -Slug "cooling-buildout" -Open   # auto-opens after create
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Repo` | Yes | Exact repo name |
| `-Slug` | Yes | Short kebab-case description, e.g. `cooling-buildout`. Becomes part of the filename |
| `-Open` | No | Switch. Opens the new file in VS Code if available, otherwise Notepad |

Creates: `issues\ha-config_cooling-buildout.md` (repo prefix is derived automatically). Files are written with a trailing newline so the pre-commit `end-of-file-fixer` hook does not flag them on every commit.

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

The `labels` field accepts a comma-separated list — each label is passed as a separate `--label` argument to `gh`, so all labels are applied correctly.

The script validates that `repo` and `title` are present, warns if the body still contains template placeholder comments, and aborts if the repo name is not in `repos.ps1`.

After a successful publish, the script writes `published_url` back into the file's frontmatter:

```yaml
published_url: https://github.com/wkcollis1-eng/home-assistant-config/issues/2
```

This creates a bidirectional trace — the local file records where it was published, and re-running `publish-issue.ps1` on the same file will warn before creating a duplicate.

---

### `list-issues.ps1`
Lists local issue drafts and/or open GitHub issues across all managed repos. Useful for reviewing what's queued locally before publishing, and for checking GitHub for duplicates. Local drafts that have already been published show a `[published]` indicator alongside their filename.

```powershell
.\list-issues.ps1                                        # local drafts only
.\list-issues.ps1 -Remote                                # GitHub open issues, all repos
.\list-issues.ps1 -Remote -Repo home-assistant-config   # one repo only
.\list-issues.ps1 -All                                   # local drafts + GitHub issues side by side
.\list-issues.ps1 -Remote -Label bug                     # filter GitHub issues by label
.\list-issues.ps1 -Remote -State closed                  # show closed instead of open issues
.\list-issues.ps1 -All -Export json                      # export all results to timestamped JSON
.\list-issues.ps1 -All -Export csv                       # export all results to timestamped CSV
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Repo` | No | Filter to a single repo. Works with all modes |
| `-Remote` | No | Switch. Fetch and display issues from GitHub via `gh` |
| `-All` | No | Switch. Show both local drafts and GitHub issues |
| `-Label` | No | Filter GitHub issues by label (passed as `--label` to `gh`). Also filters local drafts by label field in frontmatter |
| `-State` | No | GitHub issue state to query — `open` (default) or `closed` |
| `-Export` | No | Export results to a timestamped file: `json` or `csv`. Written to the Tools repo root |

Remote mode requires `gh` authenticated. Color-coded by repo — same scheme as `status-all-repos.ps1`.

---

### `issues\TEMPLATE.md`
Standard template for new issue files. Copied automatically by `new-issue.ps1` — do not edit directly. Contains frontmatter fields and section headers that match the project's issue style.

---

### `create-issue.ps1`
Opens a GitHub issue in one of the managed repos. Requires `gh` (see Prerequisites). Displays the latest CalVer tag in the target repo for release reference context.

```powershell
.\create-issue.ps1 -Repo home-assistant-config -Title "Fix DST in climate_norms_today.py"
.\create-issue.ps1 -Repo Residential-HVAC-Performance-Baseline- -Title "Add March 2026 data" -OpenInBrowser
.\create-issue.ps1 -Repo home-assistant-config -Title "Cooling build-out" -BodyFile "C:\repos\Tools\issue_body.md"
.\create-issue.ps1 -Repo home-assistant-config -Title "Fix bug" -Labels "bug","urgent" -Assignee wkcollis1-eng
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Repo` | Yes | Exact repo name (case-sensitive — see valid list in script) |
| `-Title` | Yes | Issue title |
| `-Body` | No | Issue body as an inline string |
| `-BodyFile` | No | Path to a `.md` file to use as the issue body — use this for long issues like build-out plans |
| `-Labels` | No | Array of label strings — each passed as a separate `--label` argument to `gh` (e.g. `"bug","urgent"`) |
| `-Assignee` | No | GitHub username to assign the issue to |
| `-OpenInBrowser` | No | Switch. Opens the new issue URL in your browser immediately |

> **Note:** If neither `-Body` nor `-BodyFile` is provided, `gh` opens your configured editor so you can write the body interactively. `-BodyFile` is the recommended approach for issues that already exist as Markdown documents (e.g. `GITHUB_ISSUE_1_COOLING_BUILDOUT.md`).

---

### `validate-all.ps1`
Runs `validate_month.py` from the `Residential-HVAC-Performance-Baseline-` repo. Validates all months in the CSV history by default, or a specific month. **Exits 1 if any HALT-level check fails** — safe to use as a gate before committing monthly data. The Python call is wrapped in `try/finally` so the working directory is always restored even if Python throws an uncaught exception.

```powershell
.\validate-all.ps1                    # validate all months
.\validate-all.ps1 -Month 2026-03     # validate March 2026 only
.\validate-all.ps1 -Json              # also export results to validate-results.json
```

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Month` | No | Month to validate. Accepts `YYYY-MM` or `YYYY-MM-01`. Omit to validate all months |
| `-Json` | No | Export pass/fail result and metadata to `validate-results.json` in the Tools root |

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
Pulls all repos, validates the **prior month's** existing data (the target month data doesn't exist yet — this confirms the baseline is clean before new entry begins), and creates a work queue issue with a pre-filled checklist.

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

Phase 2 is smart about releases — it validates the `-Tag` format as CalVer (`vYYYY.MM.N`) before any GitHub call, checks `git rev-list` for each repo and only tags repos that have new commits since their last tag, and fetches the new tag locally after each successful create. Repos with no changes are skipped automatically.

---

## Issue workflow

Local issue files let you draft, review, and version-control issues before they hit GitHub — useful for large build-out plans like the cooling infrastructure issue.

```powershell
# Shortcut — full publish workflow in one command:
.\publish-and-sync.ps1 issues\ha-config_filter-runtime-fix.md -OpenInBrowser

# Or step by step:
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
cd C:\repos\Tools
.\session-start.ps1    # verify environment, pull, status — aborts on failure
# ... do your Claude Code session ...
.\session-end.ps1      # status, deploy prompt, push, sync
```

That's it. The scripts encode the full workflow — nothing to remember.

For sessions where you know you won't be deploying scripts:

```powershell
.\session-end.ps1 -NoDeploy
```

For sessions with only code changes and no doc updates:

```powershell
.\session-end.ps1 -NoSync
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
When a new `.py` script is added to `home-assistant-config\scripts\` and referenced by a shell command in `configuration.yaml`, add one entry to the `$deployMap` in `deploy-to-ha.ps1`. The map uses `$ReposRoot` (from `repos.ps1`) and `$SambaSharePath` (from `common.ps1`) so paths adapt automatically to any `-ReposRoot` override:

```powershell
$deployMap = @{
    "$ReposRoot\home-assistant-config\scripts\climate_norms_today.py" = "$SambaSharePath\climate_norms_today.py"
    "$ReposRoot\home-assistant-config\scripts\csv_manager.py"         = "$SambaSharePath\csv_manager.py"
    "$ReposRoot\home-assistant-config\scripts\setback_csv.py"         = "$SambaSharePath\setback_csv.py"
    # Add new scripts here:
    "$ReposRoot\home-assistant-config\scripts\new_script.py"          = "$SambaSharePath\new_script.py"
}
```

No other changes are needed.

### Adding a new repo to the toolkit
Edit `repos.ps1` — add the repo name to `$Repos` and its clone URL to `$RepoUrls`. The `$RepoMap` (with `.Path` and `.Url` properties per repo) is rebuilt automatically. Every script that dot-sources `repos.ps1` will automatically include the new repo. Then run `.\clone-all-repos.ps1` to pull it locally.

---

## Repo structure

```
C:\repos\
├── Tools\                          ← this repo
│   ├── README.md
│   ├── repos.ps1                   ← single source of truth for repo list
│   ├── common.ps1                  ← shared Assert-Environment, dot-sourced by all scripts
│   ├── .pre-commit-config.yaml
│   ├── CLAUDE_TOOLS.md             ← ultra-min Claude Code reference
│   ├── inject-tools-ref.ps1
│   ├── bootstrap.ps1
│   ├── session-start.ps1
│   ├── session-end.ps1
│   ├── publish-and-sync.ps1
│   ├── release.ps1
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

**`bootstrap.ps1` fails at a prerequisite check**
Install the missing tool (git, python, or gh — links are printed), then re-run `bootstrap.ps1`. It is safe to re-run — completed steps are skipped.

**`release.ps1` fails with HALT on HVAC repo**
`validate-all.ps1` found a data integrity error for the target month. Fix the CSV data, commit the fix, and re-run `release.ps1`. Do not use `-SkipValidation` to bypass a legitimate data error.

**`publish-and-sync.ps1` shows duplicates but I want to publish anyway**
Answer `n` at the duplicate prompt to cancel, or pass `-SkipDuplicateCheck` to bypass it. Note that if you publish a duplicate, `publish-issue.ps1` will still succeed — it's your responsibility to close the duplicate on GitHub afterward.

**`session-start.ps1` aborts at environment check**
`verify-system.ps1` found a hard failure — the output above it will show exactly which check failed. Resolve it (missing tool, git identity, unauthenticated gh, diverged repo) and re-run `session-start.ps1`.

**`session-end.ps1` aborts at deploy step**
`deploy-to-ha.ps1` failed — hash mismatch or Samba share unreachable. Do not push until resolved. Fix the deploy issue and re-run `session-end.ps1 -Deploy` to resume from the deploy step.

**`session-end.ps1` deploy prompt always shows N default but I changed a .py file**
The auto-detect uses `@{u}..HEAD` to capture all unpushed commits, not just the last one. If the `.py` change hasn't been committed yet it won't be detected. Commit first, then run `session-end.ps1` or pass `-Deploy` to skip detection. If the repo has no upstream tracking branch yet, the diff falls back to `HEAD~1..HEAD` (single-commit guard).

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
