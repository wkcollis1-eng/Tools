# tools

PowerShell utility scripts for managing the wkcollis1-eng GitHub repositories and Home Assistant Green deployment from a Windows PC.

**Repos managed:**
- `home-assistant-config`
- `Residential-HVAC-Performance-Baseline-`
- `Lifepo4-Battery-Banks`
- `DIY-LiFePO4-UPS`
- `tools` (this repo)

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

### GitHub CLI (`gh`) — required for `create-release.ps1`
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

### 3. (Optional) Add tools to your PowerShell PATH

To run the scripts from any directory without typing the full path:

```powershell
# Add to current session only:
$env:PATH += ";C:\repos\tools"

# To make permanent, add to your PowerShell profile:
notepad $PROFILE
# Add this line at the bottom:
# $env:PATH += ";C:\repos\tools"
```

### 4. Install pre-commit hooks (optional but recommended)

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

### `clone-all-repos.ps1`
Clones all five repos into `C:\repos\`. Safe to re-run — skips repos that already exist.

```powershell
.\clone-all-repos.ps1
```

---

### `pull-all-repos.ps1`
Runs `git pull` in every repo. **Run this at the start of every session** before opening Claude Code.

```powershell
.\pull-all-repos.ps1
```

---

### `status-all-repos.ps1`
Runs `git status --short` in every repo. Use this for a quick pre-commit sanity check.

```powershell
.\status-all-repos.ps1
```

---

### `deploy-to-ha.ps1`
Copies live Python scripts from `home-assistant-config` to the HA Green Samba share. **Run this after any commit that modifies a script file.**

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
Runs `git push` in every repo. Use at the end of a session after all commits are made.

```powershell
.\push-all-repos.ps1
```

> Note: this pushes whatever is committed locally. If a repo has unpushed commits on a branch other than `main`, they will also push. Run `status-all-repos.ps1` first to confirm you know what's going out.

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
Installs pre-commit hooks in all five repos. Run once after initial clone. Also installs `pre-commit` via pip if it is not already present.

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

## Daily workflow

```powershell
# --- Start of session ---
cd C:\repos\tools
.\pull-all-repos.ps1          # sync everything from GitHub
.\status-all-repos.ps1        # confirm clean state before starting

# --- Do your Claude Code session ---
# (Claude Code commits per-repo as it works)

# --- End of session ---
.\status-all-repos.ps1        # confirm what's staged/committed
.\deploy-to-ha.ps1            # ONLY if a script file changed
.\push-all-repos.ps1          # push all repos to GitHub
```

---

## Monthly update workflow

On the 1st of each month after utility bills arrive:

```powershell
# 1. Pull everything
.\pull-all-repos.ps1

# 2. Run the monthly update Claude Code session
#    (enters bill data, updates CSVs, commits across repos)

# 3. Create releases for repos that changed
.\create-release.ps1 -Repo home-assistant-config -Tag v2025.06.1 -Title "June 2025 monthly update"
.\create-release.ps1 -Repo Residential-HVAC-Performance-Baseline- -Tag v2025.06.1 -Title "June 2025 monthly update"

# 4. Push everything
.\push-all-repos.ps1
```

---

## Extending the deploy map

When a new Python script is added to `home-assistant-config\scripts\` and referenced by a shell command in `configuration.yaml`, add it to `deploy-to-ha.ps1`:

```powershell
$deployMap = @{
    "C:\repos\home-assistant-config\scripts\climate_norms_today.py" = "\\homeassistant\config\scripts\climate_norms_today.py"
    "C:\repos\home-assistant-config\scripts\csv_manager.py"         = "\\homeassistant\config\scripts\csv_manager.py"
    "C:\repos\home-assistant-config\scripts\setback_csv.py"         = "\\homeassistant\config\scripts\setback_csv.py"
    # Add new scripts here:
    "C:\repos\home-assistant-config\scripts\new_script.py"          = "\\homeassistant\config\scripts\new_script.py"
}
```

No other changes are needed. The script loops the map automatically.

---

## Repo structure

```
C:\repos\
├── tools\                          ← this repo
│   ├── README.md
│   ├── .pre-commit-config.yaml
│   ├── clone-all-repos.ps1
│   ├── pull-all-repos.ps1
│   ├── push-all-repos.ps1
│   ├── status-all-repos.ps1
│   ├── deploy-to-ha.ps1
│   ├── install-precommit-all.ps1
│   └── create-release.ps1
├── home-assistant-config\
├── Residential-HVAC-Performance-Baseline-\
├── Lifepo4-Battery-Banks\
└── DIY-LiFePO4-UPS\
```

---

## Troubleshooting

**`deploy-to-ha.ps1` reports "Missing" for a script**
The local file path in `$deployMap` does not exist. Confirm the script is committed and pulled to `C:\repos\home-assistant-config\scripts\`.

**`deploy-to-ha.ps1` fails to copy (access denied or path not found)**
The Samba share is not mounted. Open File Explorer and navigate to `\\homeassistant\config` — you may need to enter HA credentials. Once connected, re-run the script.

**`pre-commit` blocks a commit with a YAML error**
Fix the YAML in the flagged file, then `git add` the file again and retry the commit. The hook output will show the exact line number.

**`gh` is not recognized**
GitHub CLI is not installed or not on PATH. Install from https://cli.github.com and restart PowerShell.

**`create-release.ps1` fails with "release already exists"**
A tag with that name was already pushed. Either delete the tag on GitHub and re-run, or increment the patch number (e.g. `v2025.06.2`).

**`git pull` reports merge conflicts**
Do not force-push. Resolve conflicts manually in the affected file, then `git add` and `git commit`. If Claude Code made the conflicting commit, check CLAUDE.md for the session rules that govern how it handles existing content.
