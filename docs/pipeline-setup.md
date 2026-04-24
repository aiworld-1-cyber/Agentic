# UAT End-to-End Pipeline Setup Guide

## Overview
This guide covers the complete setup of the Salesforce UAT End-to-End GitHub Actions Pipeline. The pipeline orchestrates PR validation, code scanning, deployment, and CRT smoke testing with comprehensive governance controls.

---

## Required Secrets

All secrets must be created at the **repository** level in GitHub Settings → Secrets and variables → Actions.

| Secret | Description | How to Create |
|--------|-------------|--------------|
| `CRT_UAT_AUTHURL` | SFDX Auth URL for UAT org | `sfdx org display --targetusername=uat --json` → copy `sfdxAuthUrl` value |
| `GH_PAT` | Fine-Grained Personal Access Token | 1. Settings → Developer settings → Fine-grained tokens → New token<br>2. Permissions: `actions:read`, `contents:read`, `variables:read/write`<br>3. Copy token value |
| `CRT_API_TOKEN` | Copado RunTest GraphQL API token | Contact Copado admin for API token |
| `CX_CLIENT_SECRET` | **Optional** — CheckMarx client secret (enables Job 5) | Skip if not using CheckMarx |
| `FOD_CLIENT_SECRET` | **Optional** — Fortify client secret (enables Job 6) | Skip if not using Fortify |

**To create SFDX Auth URL:**
```bash
# 1. Authenticate to target org
sfdx org login web --alias uat

# 2. Display auth URL
sfdx org display --targetusername=uat --json | jq -r '.result.sfdxAuthUrl'

# 3. Copy output and paste into GitHub Secret
```

---

## Required Variables

Variables are configured at the **repository** level in GitHub Settings → Variables.

| Variable | Type | Default | Description | SCA Controlled |
|----------|------|---------|-------------|----------------|
| `ORG_ALIAS` | Var | `uat` | Salesforce org alias for SFDX commands | ❌ |
| `COVERAGE_THRESHOLD` | Var | `85` | Minimum Apex code coverage % required to pass validation | ❌ |
| `SOURCE_DIR` | Var | `force-app/main/default` | Path to Salesforce source directory | ❌ |
| `SFDX_AUTH_SECRET_NAME` | Var | `CRT_UAT_AUTHURL` | Name of the secret containing SFDX auth URL | ❌ |
| `SCA_ENFORCEMENT_MODE` | Var | `enforce` | **Security scanning enforcement level** ← **Key setting**<br>- `enforce`: Expired waivers FAIL pipeline<br>- `warn`: All violations warnings only (does not block)<br>- `off`: All SCA steps skipped (no scanning) | ✅ |
| `DELTA_FROM_COMMIT` | Var | *(must be set)* | Baseline SHA for delta calculation (auto-updated on deploy) | ❌ |
| `CRT_JOB_ID` | Var | `115686` | CRT test job ID | ❌ |
| `CRT_PROJECT_ID` | Var | `73283` | CRT project ID | ❌ |
| `CRT_ORG_ID` | Var | `43532` | CRT org ID | ❌ |

### SCA_ENFORCEMENT_MODE Behavior Matrix

| Mode | Expired Waiver | No Waiver | SCA Steps | Use Case |
|------|---|---|---|---|
| `enforce` | ❌ FAIL | ⚠️ WARN | ✅ RUN | Production-grade security (default) |
| `warn` | ⚠️ WARN | ⚠️ WARN | ✅ RUN | Onboarding/ramping up security practices |
| `off` | ⏭️ SKIP | ⏭️ SKIP | ❌ SKIP | Initial setup, non-code repos |

---

## Initial Setup Checklist

### 1. Create GitHub Secrets

```bash
# In GitHub UI → Settings → Secrets and variables → Actions
# Create secrets:
✅ CRT_UAT_AUTHURL         (SFDX auth URL)
✅ GH_PAT                  (Fine-grained token)
✅ CRT_API_TOKEN           (Copado GraphQL token)
⬜ CX_CLIENT_SECRET        (optional - CheckMarx)
⬜ FOD_CLIENT_SECRET       (optional - Fortify)
```

### 2. Create GitHub Variables

```bash
# In GitHub UI → Settings → Variables
✅ ORG_ALIAS               (default: uat)
✅ COVERAGE_THRESHOLD      (default: 85)
✅ SOURCE_DIR              (default: force-app/main/default)
✅ SFDX_AUTH_SECRET_NAME   (default: CRT_UAT_AUTHURL)
✅ SCA_ENFORCEMENT_MODE    (default: enforce) ← CRITICAL
✅ DELTA_FROM_COMMIT       (set to current main branch SHA)
✅ CRT_JOB_ID              (default: 115686)
✅ CRT_PROJECT_ID          (default: 73283)
✅ CRT_ORG_ID              (default: 43532)
```

**To set DELTA_FROM_COMMIT:**
```bash
git log -1 --format=%H main  # Output the current main branch SHA
# Use this SHA as the value for DELTA_FROM_COMMIT
```

### 3. Configure Branch Protection Rules

**Protected branch:** `uat`

| Setting | Value |
|---------|-------|
| Require status checks | ✅ |
| Required checks | `salesforce-validation`, `sca-sast-stage`, `approval-merge-gate` |
| Require branches be up to date | ✅ |
| Require code review before merge | ✅ (1 approval) |
| Require review from code owners | ⬜ (if applicable) |
| Allow auto-merge | ❌ |

### 4. Create `pr_packages` Orphan Branch

```bash
# Initialize orphan branch for storing deployment packages
git checkout --orphan pr_packages
git rm -rf .
git commit --allow-empty -m "Initial commit for pr_packages orphan branch"
git push origin pr_packages
```

**Purpose:** Stores deployment package artifacts with 90-day retention for audit trail and rollback reference.

### 5. Configure SCA Enforcement Level

**Recommendation by project phase:**

| Phase | Mode | Reason |
|-------|------|--------|
| Initial Setup | `off` | Establish baseline without blocking PRs |
| Ramp-up | `warn` | Visibility into violations without blocking |
| Mature | `enforce` | Full governance with waiver expiry checks |

**To change mode:**
```bash
# In GitHub UI → Settings → Variables → SCA_ENFORCEMENT_MODE
# Update value and commit
```

---

## Waiver File Setup

### Salesforce Code Analyzer Waivers
**File:** `.github/sf-scanner-waivers.csv`  
**Location:** Main branch only (PR copies ignored)

```csv
rule,file_pattern,message_contains,severity_threshold,expiry,reason,approved_by,approved_date,ticket,status
ApexDoc,MyClass.cls,,3,10-05-2026,Justification here,team-lead,10-04-2026,PROJ-123,ACTIVE
```

- Fetched from **main branch** via GitHub API during validation
- Waivers on PR branch are **ignored**
- Expired waivers fail pipeline (in `enforce` mode)
- See [sca-waivers.md](sca-waivers.md) for detailed schema

### npm Audit Waivers
**File:** `.github/sca-waivers.json`  
**Location:** Repository root

```json
[
  {
    "package": "lodash",
    "severity": "high",
    "advisory": "GHSA-35jh-r3h4-6jhm",
    "reason": "No fix available.",
    "expires": "2026-05-30",
    "approved_by": "platform-security"
  }
]
```

See [sca-waivers.md](sca-waivers.md#npm-audit-waivers) for detailed schema.

---

## DELTA_FROM_COMMIT Auto-Update Mechanism

After each successful deployment to UAT, the workflow automatically updates the `DELTA_FROM_COMMIT` variable via GitHub API.

### How it works

1. **Deployment succeeds** → Job `deploy-after-merge` runs
2. **Step 5:** Commits current HEAD to `pr_packages` branch
3. **Step 6:** Updates `DELTA_FROM_COMMIT` variable with new HEAD SHA
   ```bash
   curl -X PATCH https://api.github.com/repos/.../actions/variables/DELTA_FROM_COMMIT
   ```
4. **Next PR:** Uses updated SHA as delta baseline

### Manual Reset (if needed)

If auto-update fails or you need to reset the baseline:
```bash
# 1. Get desired baseline SHA
git log --oneline | head -1

# 2. Update in GitHub UI → Settings → Variables → DELTA_FROM_COMMIT
# Or via API:
curl -X PATCH \
  -H "Authorization: Bearer $GH_PAT" \
  https://api.github.com/repos/$OWNER/$REPO/actions/variables/DELTA_FROM_COMMIT \
  -d '{"name":"DELTA_FROM_COMMIT","value":"<new-sha>"}'
```

---

## No-Delta Skip Behavior

When a PR has no changes detected in Salesforce source files:

| Condition | Behavior |
|-----------|----------|
| No `package.xml` members | ✅ PR can merge (no deployment needed) |
| No `destructiveChanges.xml` members | ✅ PR can merge (no deletions) |
| Branch protection check | ℹ️ Status checks skipped (not required) |
| Manual approval | ✅ Still required (PR review gate) |

**Example:** Documentation-only PR will skip all validation jobs but still requires approval.

---

## Troubleshooting Initial Setup

| Issue | Cause | Solution |
|-------|-------|----------|
| "SFDX_AUTH_SECRET_NAME not found" | Secret name mismatch | Verify secret name in GitHub → Settings → Secrets |
| "org login: INVALID_SFDX_AUTH_URL" | Invalid or expired auth URL | Re-run: `sfdx org login web --alias uat` |
| "GH_PAT: insufficient permissions" | Token missing scope | Regenerate PAT with `variables:read/write` scope |
| "DELTA_FROM_COMMIT: undefined" | Variable not set | Set to current main SHA: `git log -1 --format=%H main` |
| "SCA_ENFORCEMENT_MODE not recognized" | Invalid mode value | Set to `enforce`, `warn`, or `off` |

See [troubleshooting.md](troubleshooting.md) for detailed diagnostics.

---

## Security Best Practices

1. **Rotate secrets quarterly** — Re-generate GH_PAT and SFDX Auth URLs
2. **Use fine-grained PAT** — Limit token scope to variables only
3. **Audit waiver approvals** — Track who approved each waiver
4. **Monitor SCA_ENFORCEMENT_MODE** — Escalate from `off` → `warn` → `enforce` over time
5. **Review pr_packages** — Periodically audit deployment history
6. **Disable CheckMarx/Fortify** — Set secrets only if actively using those scanners

---

## Performance Tuning

| Parameter | Default | Tuning |
|-----------|---------|--------|
| `COVERAGE_THRESHOLD` | `85%` | ↓ Reduce if high-variance tests; ↑ increase for critical code |
| Poll interval | `15s` (deploy) / `30s` (CRT) | ↓ More frequent for fast changes; ↑ reduce API load |
| Max polls | `240` (4 hours) | ↑ Increase for long deployments |

---

## Support & Documentation

- [SCA Waivers Schema & Governance](sca-waivers.md)
- [PR Review & Deployment Runbook](manual_runbook.md)
- [Troubleshooting Guide](troubleshooting.md)
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Salesforce CLI Reference](https://developer.salesforce.com/docs/cli)
