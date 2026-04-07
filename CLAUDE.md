# Claude Code Guidelines

## HA/Samba script testing rules

NEVER run deploy-to-ha.ps1 without -SambaOverride during a test loop.
NEVER run session-end.ps1 without -NoDeploy during a test loop.
The shadow target is: C:\repos\Tools\test-fixtures\fake-ha\scripts

Test loop for any script that touches Samba:
1. STAGE: Make the code change
2. TEST:  .\deploy-to-ha.ps1 -SambaOverride "C:\repos\Tools\test-fixtures\fake-ha\scripts"
    .\verify-system.ps1 -NoFetch   (read-only — safe to run against real share)
3. VALIDATE: Inspect output. Check shadow dir contents and DEPLOY_VERSION.txt equivalent.
4. CORRECT: Fix any errors in the script. Do not commit yet.
5. RETEST:  Repeat step 2 until clean exit 0 with all hashes verified.
6. COMMIT:  Only after clean retest. Tag the commit.
7. REAL DEPLOY: You (Bill) run .\deploy-to-ha.ps1 (no override) manually after reviewing.

---

## Project Structure

- `/repos/Tools`: Central management toolkit.
- `/repos/home-assistant-config`: Live configuration and scripts for HA Green.
- `/repos/DIY-LiFePO4-UPS`: UPS control logic.
- `/repos/Lifepo4-Battery-Banks`: Battery bank monitoring.
- `/repos/Residential-HVAC-Performance-Baseline-`: HVAC performance baseline data.
