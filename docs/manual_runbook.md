# Manual Runbook

This guide covers manual operations: PR approval/merge workflow and emergency rollbacks.

---

## Section 1: PR Review & Approval Workflow

The **only human gate** before deployment to UAT is **PR approval**.

### Flow

```
Developer creates PR on uat
    ↓
Pipeline runs: salesforce-validation, sca-sast-stage, automated-governance
    ↓
Pipeline posts results as PR comments
    ↓
Tech Lead reviews PR + tests
    ↓
Tech Lead approves PR ("Request changes" or "Approve")
    ↓
Approval-merge-gate job runs
    ↓
PR is automatically merged to uat
    ↓
Deploy-after-merge job deploys to UAT org
    ↓
CRT smoke tests run post-deployment
```

### PR Review Checklist (for Tech Lead)

**Before Approving:**

- [ ] Code review passed (correctness, standards compliance)
- [ ] All pipeline checks green (no failing status checks)
  - [ ] salesforce-validation ✓
  - [ ] sca-sast-stage ✓
  - [ ] automated-governance ✓
  - [ ] checkmarx-sast ✓ (if enabled)
  - [ ] fortify-sast-dast ✓ (if enabled)
- [ ] SCA governance report reviewed
  - [ ] No unexpected expired waivers
  - [ ] No unwaived violations (or acceptable warnings)
- [ ] Apex test coverage ≥ threshold (default 85%)
- [ ] No destructive changes (unless intentional and documented)
- [ ] PR description explains **what** and **why**

### Approval

On the PR page:

1. Click **"Review changes"** (top right)
2. Select **"Approve"**
3. (Optional) Leave comment with test results or sign-off
4. Click **"Submit review"**

**⚠️ Important:** Approval must be within **24 hours** of the last approval for the merge-gate job to accept it.

### After Approval

- Approval-merge-gate job automatically triggers
- PR is merged to `uat` branch
- **Do NOT manually merge** — the pipeline does this
- Deployment begins automatically on `uat`

### Monitoring Deployment

1. Go to **Actions** tab
2. Find `deploy-after-merge` run
3. Click to view real-time logs
4. Wait for **CRT smoke tests** to complete (final job)
5. Check PR comment for CRT test results

---

## Section 2: Emergency Rollback

### When to Rollback

- Critical production defect discovered post-deployment
- Data integrity issue in UAT
- Performance degradation blocking UAT testing
- Unexpected breaking changes

### Rollback Procedure

#### Step 1: Find the Target Commit

You want to revert **to** a previous commit (not from a PR).

```bash
# View recent commits on uat
git log uat --oneline -20

# Find the commit before the problematic deploy
# Example output:
# a1b2c3d (HEAD -> uat) Merge PR #45 - Bad deployment
# e4f5g6h Merge PR #44 - Last good deployment  ← REVERT TO THIS
# i7j8k9l Merge PR #43 - Earlier deployment
```

Copy the commit SHA (e.g., `e4f5g6h`).

#### Step 2: Trigger Rollback

1. Go to **Actions** tab
2. Select **"UAT End-to-End Pipeline"** workflow
3. Click **"Run workflow"** dropdown
4. Select branch: `uat`
5. Fill in inputs:
   - **action**: `rollback` (required)
   - **rollback_commit_sha**: `e4f5g6h` (paste commit SHA, required)
   - **rollback_pr_number**: (optional) PR number that introduced the issue (for notification)
6. Click **"Run workflow"**

#### Step 3: Monitor Rollback

1. Workflow triggers `rollback` job
2. Builds reverse delta (new components = destructive)
3. Deploys to UAT org
4. Posts notification to PR (if PR number provided)

Monitor logs in **Actions** tab for success/failure.

#### Step 4: Verify Rollback

```bash
# Check org state
sf org open --alias uat
# Verify manually in Salesforce UI that old version is active
```

#### Step 5: Post-Mortem

1. Create GitHub issue: "Rollback from commit XYZ — root cause investigation"
2. Tag team members
3. Schedule post-mortem meeting
4. Document findings and preventive measures

---

### What Rollback Does

**Reverse Delta Calculation:**
- Compares current state (HEAD) to rollback target commit
- Components added since target → marked for deletion
- Components modified since target → re-deployed from target version
- Components deleted since target → restored

**Deployment:**
- Uses `--pre-destructive-changes` to delete new components first
- Then deploys restored components
- Net effect: Salesforce org reverts to rollback commit state

**Example:**
```
Timeline:
  e4f5g6h (rollback target): Class A v1, Class B v1
      ↓
  a1b2c3d (current): Class A v2 (modified), Class C (new)

Rollback action:
  1. DELETE Class C
  2. Deploy Class A v1 (restore)
  → Org reverts to e4f5g6h state
```

---

## Section 3: Monitoring & Alerts

### Key Metrics to Watch

**After each deployment:**
- ✅ Deployment status: Success/Failure in Actions
- ✅ CRT test results: Passed/Failed in PR comment
- ✅ Code coverage: Must be ≥ threshold
- ✅ SCA violations: Active waivers vs. unwaived

### Deployment Artifacts

Check **pr_packages** branch for audit trail:
```bash
git log pr_packages --oneline
# a1b2c3d Deployment package from commit xyz
# e4f5g6h Deployment package from commit abc

# Inspect specific deployment
git show pr_packages:deployment-info.json
# Shows: timestamp, deployed_by, branch, merge_base
```

### Approval Tracking

View all approvals via GitHub API:
```bash
gh pr list --state closed --base uat --limit 20
# Shows merged PRs with approver + merge time
```

---

## Section 4: Common Operations

### Rerun Failed Pipeline Step

If a step fails due to transient error:

1. Go to **Actions** → failed workflow run
2. Click **"Re-run failed jobs"** (top right)
3. Monitor re-run logs

**⚠️ Note:** Do NOT re-run after approving — will re-merge PR (safe, but redundant).

### Bypass SCA Check (Temporary)

For emergencies, temporarily disable SCA enforcement:

```bash
# Set SCA_ENFORCEMENT_MODE to "warn"
# Settings → Secrets and variables → Variables → SCA_ENFORCEMENT_MODE
# Change value to: warn
# Save
```

All SCA violations become warnings (pipeline no longer fails).

**Reset after emergency:**
```bash
# Change SCA_ENFORCEMENT_MODE back to: enforce
```

### Force Revalidation on PR

If validation was skipped (e.g., PR marked draft → ready):

1. Go to PR
2. Click **"Commit details"**
3. Re-trigger workflow: Push empty commit:
   ```bash
   git commit --allow-empty -m "Trigger revalidation"
   git push
   ```

---

## Section 5: Troubleshooting Deployments

See [docs/troubleshooting.md](troubleshooting.md) for detailed error diagnosis and fixes.

Quick reference:

| Error | Likely Cause | Fix |
|-------|--------------|-----|
| `Validation failed: Apex test coverage` | Tests failing or coverage < 85% | Run tests locally, fix failures, recommit |
| `Deployment failed: Metadata conflicts` | Deploy order issue | Check order in package.xml, add dependencies |
| `CRT tests failed` | UAT org in bad state | Check org state, consider rollback |
| `EXPIRED_WAIVER` | SCA waiver past expiry | Renew waiver or fix violation |
| `Merge conflict` | UAT ahead of PR | Rebase PR on latest uat |

---

## Section 6: Rollback Decision Tree

```
Issue detected in UAT?
    ├─ Yes, critical (data/security)
    │   └─ ROLLBACK immediately
    │       1. Find last good commit
    │       2. Trigger rollback workflow
    │       3. Verify org state
    │       4. Notify team
    │       5. Root cause analysis
    │
    ├─ No, but blocking testing
    │   └─ ROLLBACK or HOT FIX?
    │       ├─ If fix is <1 hour → Create hot fix PR (expedited review)
    │       └─ If fix >1 hour → ROLLBACK
    │
    └─ No, minor issue
        └─ Continue UAT, create bug fix PR
           (no rollback needed)
```

---

## Links

- [Pipeline Setup](pipeline-setup.md)
- [SCA Waivers](sca-waivers.md)
- [Troubleshooting](troubleshooting.md)
