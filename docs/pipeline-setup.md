# UAT End-to-End Pipeline Setup Guide

This guide provides all required configuration, secrets, and variables needed to run the UAT end-to-end GitHub Actions pipeline.

## Overview

The pipeline (`e2e-uat-pipeline.yml`) automates Salesforce development for the UAT org with 10 integrated jobs:

1. **setup** — Evaluates scanner availability (CheckMarx, Fortify)
2. **salesforce-validation** — PR validation, delta detection, Apex coverage, SCA
3. **sca-sast-stage** — npm audit with waiver checking
4. **automated-governance** — Full test suite, coverage enforcement, destructive change checks
5. **checkmarx-sast** — SAST scanning (conditional, requires secret)
6. **fortify-sast-dast** — SAST + DAST scanning (conditional, requires secret)
7. **approval-merge-gate** — Requires PR approval before merge to UAT
8. **deploy-after-merge** — Deploys delta to UAT org after merge
9. **trigger-crt-tests** — Triggers CRT smoke tests post-deployment
10. **rollback** — Rollback to a previous commit (manual trigger)

---

## Required Secrets

Configure these in **Settings → Secrets and variables → Actions**.

| Secret Name | Description | How to Create | Required? |
|---|---|---|---|
| `CRT_UAT_AUTHURL` | SFDX Auth URL for UAT org | 1. `sf org login sfdx-url --sfdx-url-input <value> --alias uat --set-default` <br> 2. `sf org login sfdx-url display --json` → copy `sfdxAuthUrl` <br> 3. Create secret in GitHub with full URL (includes `InstanceUrl`, `ClientId`, etc.) | ✅ Yes |
| `GH_PAT` | Fine-Grained Personal Access Token | 1. Go to GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens <br> 2. New token with scope: `Actions: read+write`, `Variables: read+write`, `Contents: read+write` <br> 3. Copy token and paste into secret | ✅ Yes |
| `CRT_API_TOKEN` | Copado Robotic Testing GraphQL API token | 1. Log in to CRT portal <br> 2. Generate API token from user profile <br> 3. Paste into secret | ✅ Yes |
| `CX_CLIENT_SECRET` | CheckMarx AST client secret | 1. From CheckMarx dashboard, create API credentials <br> 2. Only required if CheckMarx scanning is enabled | ⬜ Optional |
| `FOD_CLIENT_SECRET` | Fortify on Demand client secret | 1. From Fortify dashboard, generate API token <br> 2. Only required if Fortify scanning is enabled | ⬜ Optional |

---

## Required Variables

Configure these in **Settings → Secrets and variables → Actions** (Variables section).

| Variable Name | Default | Description | Required? |
|---|---|---|---|
| `ORG_ALIAS` | `uat` | Salesforce org alias (used with `sf` CLI) | ⬜ Optional |
| `COVERAGE_THRESHOLD` | `85` | Minimum Apex test coverage % (fails if below) | ⬜ Optional |
| `SOURCE_DIR` | `force-app/main/default` | Source directory for Salesforce metadata | ⬜ Optional |
| `SFDX_AUTH_SECRET_NAME` | `CRT_UAT_AUTHURL` | Name of the secret storing the SFDX Auth URL | ⬜ Optional |
| `DELTA_FROM_COMMIT` | (required to set) | Baseline commit SHA for delta calculations (auto-updated after each deploy) | ✅ Yes |
| `FCLI_BOOTSTRAP_VERSION` | (optional) | Salesforce CLI version pin (if omitted, latest is used) | ⬜ Optional |
| `SCA_ENFORCEMENT_MODE` | `enforce` | Controls static code analysis behavior: <br> • `enforce` — expired waivers fail pipeline <br> • `warn` — all violations are warnings only <br> • `off` — skip all SCA steps | ⬜ Optional |
| `CRT_PROJECT_ID` | `73283` | CRT project ID (from CRT dashboard) | ⬜ Optional |
| `CRT_JOB_ID` | `115686` | CRT job ID (from CRT dashboard) | ⬜ Optional |
| `CRT_ORG_ID` | `43532` | CRT org ID (from CRT dashboard) | ⬜ Optional |

### How to Set Variables

1. Go to **Settings → Secrets and variables → Actions → Variables**
2. Click **New repository variable**
3. Enter name and value
4. Click **Add variable**

Example: Setting `DELTA_FROM_COMMIT`
```bash
# First, find a baseline commit on the uat branch
git log uat --oneline | head -1
# Copy the commit SHA and set as variable:
# Name: DELTA_FROM_COMMIT
# Value: <commit-sha>
```

---

## Branch Protection Rules

To enforce the approval gate, configure branch protection on `uat`:

1. Go to **Settings → Branches → Branch protection rules**
2. Create rule for pattern: `uat`
3. Enable:
   - ✅ Require a pull request before merging
   - ✅ Require approvals (1 approval minimum)
   - ✅ Require status checks to pass before merging (select all workflow jobs)
   - ✅ Require branches to be up to date before merging
4. Save

---

## Workflow Triggers & Behavior

### Pull Request to `uat`
Triggered when PR is created/updated targeting the `uat` branch:
- Paths monitored: `force-app/**`, `.github/workflows/e2e-uat-pipeline.yml`, `.github/sf-scanner-waivers.csv`
- Actions: `opened`, `reopened`, `synchronize`, `edited`, `ready_for_review`

**Jobs that run:**
- `setup` ✓
- `salesforce-validation` ✓ (validates delta, checks coverage, scans for SCA violations)
- `sca-sast-stage` ✓ (npm audit)
- `automated-governance` ✓ (if delta detected)
- `checkmarx-sast` (if secret configured)
- `fortify-sast-dast` (if secret configured)

**Output:** 
- PR comment with validation results
- SCA governance report (if violations found)

### Pull Request Review (Approved)
Triggered when a reviewer approves the PR:

**Jobs that run:**
- `approval-merge-gate` — Verifies approval is fresh (<24h), merges PR to `uat`

**Output:**
- PR is merged
- Triggers `deploy-after-merge` workflow on `uat` branch

### Push to `uat` (after merge)
Triggered when commits are pushed to `uat` branch (usually after PR merge):

**Jobs that run:**
- `deploy-after-merge` — Deploys delta to UAT org
- `trigger-crt-tests` — Runs CRT smoke tests post-deployment

**Output:**
- Deployment artifacts uploaded
- CRT test results posted to PR comment
- `DELTA_FROM_COMMIT` variable updated for rollback reference

### Manual Workflow Dispatch
Triggered via **Actions** tab with manual input:
- `scanner`: Choose `all`, `checkmarx`, or `fortify` scanners to run
- `action`: Choose `deploy` or `rollback`
- `rollback_commit_sha`: (for rollback) commit SHA to revert to
- `rollback_pr_number`: (optional) PR number to notify of rollback

---

## pr_packages Branch

The pipeline commits all deployment artifacts to an orphan branch: **`pr_packages`**

**Purpose:**
- Audit trail of all deployments to UAT
- Rollback reference — always has the most recent `deployment-info.json`
- Artifact storage (90-day GitHub retention)

**Content per deployment:**
```
package.xml                    # Metadata manifest
destructiveChanges.xml         # Deleted components (if any)
components.zip                 # Full delta source
deployment-info.json           # Metadata: timestamp, merge_base, deployed_by, branch
```

**How to retrieve past deployment:**
```bash
# List all deployments
git log pr_packages --oneline

# Checkout specific deployment
git checkout pr_packages -- deployment-info.json
cat deployment-info.json
```

---

## DELTA_FROM_COMMIT Auto-Update

The pipeline **automatically updates** `DELTA_FROM_COMMIT` after each deployment:

1. After `deploy-after-merge` succeeds
2. Uses GitHub API: `PATCH /repos/{owner}/{repo}/actions/variables/DELTA_FROM_COMMIT`
3. Sets value to the commit SHA of the deployment
4. Used as fallback for next delta calculation (if Git history unavailable in shallow clone)

**Why important:**
- Fallback for shallow clones (GitHub runners)
- Rollback reference point
- Ensures delta detection always has a baseline

---

## SCA Enforcement Modes

The `SCA_ENFORCEMENT_MODE` variable controls how the pipeline handles static code analysis violations:

| Mode | Behavior | Use Case |
|------|----------|----------|
| `enforce` (default) | Expired waivers **fail** the pipeline; active waivers are allowed | Production: strict governance with escalation paths |
| `warn` | All violations are **warnings only** — pipeline never fails on SCA | Development/MVP: collect violations without blocking |
| `off` | **Skip all SCA steps** — no scanning, no waivers checked | Initial setup/sandbox: reduce pipeline overhead |

**Example transition:**
```
Phase 1: SCA_ENFORCEMENT_MODE = "off"  (days 1–5)
↓
Phase 2: SCA_ENFORCEMENT_MODE = "warn" (days 6–14)
↓
Phase 3: SCA_ENFORCEMENT_MODE = "enforce" (day 15+)
```

---

## No-Delta Skip Behavior

If a PR changes **only documentation** (non-force-app files):

| Job | Behavior | Reason |
|-----|----------|--------|
| salesforce-validation | `has_delta=false` | No metadata to validate |
| automated-governance | Skipped | Condition: `has_delta == 'true'` |
| deploy-after-merge | Proceeds (no changes deploy) | Safe to deploy zero changes |

Use case: Update README, docs, or config without deployment.

---

## Quick Start Checklist

- [ ] **Secrets configured (3 minimum):**
  - [ ] `CRT_UAT_AUTHURL` set
  - [ ] `GH_PAT` set
  - [ ] `CRT_API_TOKEN` set
  - [ ] `CX_CLIENT_SECRET` (optional, for CheckMarx)
  - [ ] `FOD_CLIENT_SECRET` (optional, for Fortify)

- [ ] **Variables configured (1 minimum):**
  - [ ] `DELTA_FROM_COMMIT` set to a valid commit SHA
  - [ ] `SCA_ENFORCEMENT_MODE` set to `warn` or `off` for initial phase (change to `enforce` after waivers are established)

- [ ] **Branch protection enabled on `uat`:**
  - [ ] Require PR + 1 approval
  - [ ] All status checks pass
  - [ ] Up-to-date requirement

- [ ] **Waiver files created:**
  - [ ] `.github/sf-scanner-waivers.csv` on main branch (can be empty initially)
  - [ ] `.github/sca-waivers.json` on main branch (can be empty initially)

- [ ] **Documentation reviewed:**
  - [ ] Team understands PR approval flow
  - [ ] Team knows how to request rollbacks
  - [ ] SCA governance policy is clear

---

## Configuration for Initial Phase

### Week 1-2: Discovery
- Set `SCA_ENFORCEMENT_MODE=off` to skip all SCA checks
- Run PRs to understand Apex test requirements
- Document coverage gaps

### Week 3-4: Governance Setup
- Set `SCA_ENFORCEMENT_MODE=warn` to log SCA violations without failing
- Identify and document violations
- Build initial waiver files (`.github/sf-scanner-waivers.csv` and `.github/sca-waivers.json`)

### Week 5+: Enforcement
- Set `SCA_ENFORCEMENT_MODE=enforce` to enforce waiver expiry
- Maintain waiver files on main branch
- Review and approve waivers before they expire

---

## Troubleshooting

**Issue:** "Secret not found" error in actions
- **Fix:** Verify secret name exactly matches GitHub UI. Secrets are case-sensitive.

**Issue:** "DELTA_FROM_COMMIT is not set" warning
- **Fix:** Set `DELTA_FROM_COMMIT` variable to a valid commit SHA on the `uat` branch. Can be any commit; it will be updated automatically.

**Issue:** "GH_PAT does not have required permissions"
- **Fix:** Recreate the fine-grained token with scopes: `Actions: read+write`, `Variables: read+write`, `Contents: read+write`.

**Issue:** "Waiver file not found" message during SCA check
- **Fix:** Create `.github/sf-scanner-waivers.csv` on main branch (can be empty). Pipeline will not fail if file is missing.

For more detailed troubleshooting, see [troubleshooting.md](troubleshooting.md).

---

## Troubleshooting

See [docs/troubleshooting.md](troubleshooting.md) for common issues and fixes.

---

## Links

- [Waivers Documentation](sca-waivers.md)
- [Manual Runbook](manual_runbook.md)
- [Troubleshooting Guide](troubleshooting.md)
