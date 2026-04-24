# Manual Runbook: PR Review & Deployment

## Overview

This runbook provides step-by-step instructions for developers, reviewers, and deployment approvers working with the UAT End-to-End Pipeline. The pipeline enforces a single human gate: **PR review and approval before deployment**.

---

## Role Definitions

| Role | Responsibilities | Permissions |
|------|------------------|-------------|
| **Developer** | Create feature branch, implement changes, push PR | Write access to feature branch |
| **Reviewer** | Review code, request changes, approve PR | Read/comment on PR |
| **Deployment Approver** | Final approval trigger before merging to UAT | Approve PR (GitHub permission) |
| **Security Lead** | Waiver approvals, SCA_ENFORCEMENT_MODE policy | Manage `.github/sf-scanner-waivers.csv` |

---

## Part 1: Creating & Submitting a PR

### Step 1: Create feature branch
```bash
git checkout uat
git pull origin uat
git checkout -b feature/PROJ-123-implement-xyz
```

### Step 2: Implement changes
```bash
# Edit files, commit frequently
git add .
git commit -m "feat: PROJ-123 - implement new feature"
git push origin feature/PROJ-123-implement-xyz
```

### Step 3: Specify test classes (optional)
In PR body, add line:
```markdown
Tests: TestClass1, TestClass2
```

Pipeline will infer additional tests by suffix (`*Test`, `*Tests`, `*TestClass`).

### Step 4: Create PR to `uat` branch
```bash
gh pr create --base uat --head feature/PROJ-123-implement-xyz \
  --title "PROJ-123: Implement new feature" \
  --body "## Description
  
Implements feature X as per PROJ-123.

## Related Issues
- PROJ-123

## Test Classes
Tests: MyFeatureTest

## Checklist
- [x] Code reviewed locally
- [x] Test cases created
- [x] Documentation updated
"
```

### Step 5: Monitor PR validation
Pipeline automatically runs 3 jobs:
1. ✅ **salesforce-validation** — Deploys delta package, checks coverage
2. ✅ **sca-sast-stage** — npm audit, checks waivers
3. ⏳ **checkmarx-sast** / **fortify-sast-dast** — If configured

**PR shows:**
- ✅ All checks passed → Ready for review
- ❌ Failed check → Fix issue, push update
- ⏳ In progress → Wait for completion

---

## Part 2: Code Review Process

### Step 1: Request review
Assign reviewers in GitHub UI or:
```bash
gh pr edit <pr-number> --add-reviewer @reviewer1 @reviewer2
```

### Step 2: Reviewers inspect
- Check code changes, logic, test coverage
- Review SCA governance report (linked in PR comment)
- Verify deployment package contents

**Reviewer checklist:**
- [ ] Code quality & standards met
- [ ] Test coverage adequate (≥85% or per threshold)
- [ ] No security vulnerabilities (or waived)
- [ ] SCA report reviewed (no new violations)
- [ ] Documentation/comments sufficient

### Step 3: Request changes or approve

#### If issues found:
```bash
gh pr review <pr-number> --request-changes \
  --body "Found 3 issues:
1. Missing null check on line 42
2. Test class incomplete
3. Update docstring"
```

Developer fixes issues and pushes updates.

#### If all good:
```bash
gh pr review <pr-number> --approve \
  --body "Code review complete. Approved for deployment.

✅ Coverage meets threshold (87%)
✅ Test cases comprehensive
✅ No new SCA violations
✅ Ready to merge"
```

---

## Part 3: Deployment Approval & Merging

### ⚠️ Critical: Approval Timing

**Approvals are valid for 24 hours.**

If >24 hours between approval and merge, **request re-approval** before deployment.

```bash
# Check approval timestamp
gh pr view <pr-number> --json reviews -q '.reviews[-1].submittedAt'
```

### Step 1: Final approval trigger
Once code review complete, deployment approver submits approval:

```bash
gh pr review <pr-number> --approve \
  --body "✅ **APPROVED FOR DEPLOYMENT**

Approved by: DevOps Lead
Date: $(date)
Build: ${{ github.run_number }}

All validation checks passed. Ready to merge to UAT."
```

**GitHub Action triggers:** `pull_request_review` event with `state: approved`

### Step 2: Automatic merge
The pipeline job `approval-merge-gate` automatically:
1. ✅ Verifies approval freshness (<24 hours)
2. ✅ Merges PR to `uat` branch (GitHub UI shows "Merged")
3. ✅ Creates merge commit

### Step 3: Automatic deployment
Job `deploy-after-merge` automatically:
1. ✅ Builds delta package (from merge parent)
2. ✅ Deploys to UAT org (async)
3. ✅ Polls deployment status
4. ✅ Updates `DELTA_FROM_COMMIT` variable for next PR

**Timeline:**
- Approval submitted → ~5 seconds → Merged to uat
- Merge → ~30 seconds → Deploy job starts
- Deploy job → ~2-10 minutes → UAT updated

### Step 4: Monitor deployment

```bash
# Check workflow run
gh run view <run-number> -w e2e-uat-pipeline

# Or in GitHub UI → Actions → Workflow runs
```

**Deployment completes when:**
- Job `deploy-after-merge` shows ✅ (green)
- Job `trigger-crt-tests` runs smoke tests (optional)

---

## Part 4: Handling SCA Violations

### Scenario: Pipeline fails due to SCA violation

**PR shows:** ❌ `salesforce-validation` failed

**Steps to resolve:**

#### Option A: Fix the violation
```bash
# 1. View SCA report
# - Check PR comment "SCA Governance Report"
# - Or download artifact: sfdx-scanner-reports

# 2. Fix code
# Example: Add missing Apex doc comment

# 3. Push fix
git add .
git commit -m "fix: add missing ApexDoc comment (PROJ-123)"
git push

# 4. Re-run check
# - Pipeline automatically re-runs on push
# - Wait for validation job to complete
```

#### Option B: Request waiver
**Only if fix is not possible within sprint:**

```bash
# 1. Contact Security Lead
# Email with:
# - Rule name: [e.g. ApexDoc]
# - File: [e.g. MyClass.cls]
# - Severity: [3 = high]
# - Business reason: [e.g. "Legacy component, refactor tracked in PROJ-999"]
# - Target fix date: [e.g. "2026-06-30"]

# 2. Security Lead updates .github/sf-scanner-waivers.csv
# - Adds row to main branch
# - Pushes to main

# 3. Developer re-opens PR to UAT
git push origin feature/PROJ-123-implement-xyz --force

# 4. Re-run validation
# - Pipeline fetches updated waivers from main
# - Violation is now marked WAIVED
# - Validation passes
```

### SCA Report CSV Format

**Example:** From PR comment or artifact

```
Status,Rule,File,Line,Severity,Description,Expiry,Days_Left,Reason,Approved_By,Approved_Date,Ticket
WAIVED,ApexDoc,MyClass.cls,42,3,Missing comment,10-05-2026,45,Scheduled refactor,jane-lead,10-04-2026,PROJ-123
VIOLATION,NamingConvention,OldUtil.cls,108,2,Variable naming,,,No waiver,,,
EXPIRED_WAIVER,ApexDoc,LegacyCode.cls,12,3,Missing comment,01-01-2026,-115,Expired!,john-dev,01-01-2026,PROJ-999
```

| Status | Action |
|--------|--------|
| `WAIVED` | ✅ Allowed, no action needed |
| `VIOLATION` | ⚠️ Not waived; raise to team/fix |
| `EXPIRED_WAIVER` | ❌ Waiver expired; **MUST renew** |
| `WAIVED_EXPIRING_SOON` | ⏰ Renew within 30 days |

---

## Part 5: Deployment Verification

### After deployment completes

#### Check deployment status
```bash
# View latest deployment
gh run view <run-number> -w e2e-uat-pipeline --log

# Or manually in UAT org
sfdx org open --target-username uat
# → Setup → Deployments → Deployment Status
```

#### Verify components deployed
```bash
# Check git commit to pr_packages branch
git log pr_packages -5 --oneline

# Download deployment-package artifact
gh run download <run-number> --name deployment-package
ls -la deployment-package/
```

---

## Part 6: Rollback Procedure

### When to rollback

- ❌ Deployment caused critical issue in UAT
- ❌ New bugs discovered post-deployment
- ❌ Accidental deployment to wrong env
- ❌ Urgent revert needed

### Rollback steps

#### Step 1: Find target SHA
```bash
# List recent commits
git log --oneline -20

# Find commit BEFORE the problematic deployment
# Example: "a1b2c3d4 - Merged PR #42"
ROLLBACK_SHA="<prior-commit-sha>"
```

#### Step 2: Trigger rollback workflow
```bash
# Using GitHub CLI
gh workflow run e2e-uat-pipeline.yml \
  --ref uat \
  -f action=rollback \
  -f rollback_commit_sha=$ROLLBACK_SHA \
  -f rollback_pr_number=42
```

Or **in GitHub UI:**
1. Actions → e2e-uat-pipeline
2. Click "Run workflow" → workflow_dispatch
3. Set:
   - **action:** `rollback`
   - **rollback_commit_sha:** (paste SHA from step 1)
   - **rollback_pr_number:** (optional)
4. Click "Run workflow"

#### Step 3: Monitor rollback
```bash
gh run view <new-run-number> --log

# Rollback job will:
# 1. Build reverse delta (new components → destructive)
# 2. Deploy with --pre-destructive-changes
# 3. Restore prior state
```

**Timeline:** ~5-15 minutes depending on package size

#### Step 4: Verify rollback
```bash
# UAT should be at prior state
# Verify in org or check deployment report
sfdx org open --target-username uat
# → Verify components reverted
```

#### Step 5: Notify team
```bash
# Post comment on original PR
gh pr comment <pr-number> \
  --body "🔄 **Rollback Executed**

Rolled back to commit $ROLLBACK_SHA
Reason: [Brief reason]
Initiated by: [Your name]
Run: https://github.com/.../actions/runs/..."
```

### Rollback limitations

| Scenario | Can Rollback? | Notes |
|----------|---|---|
| Delete metadata | ✅ Yes | Restored from prior commit |
| Modify metadata | ✅ Yes | Reverted to prior version |
| Add metadata | ✅ Yes | Deleted via destructive changes |
| Data changes | ❌ No | Data changes not rolled back (manual Salesforce restore if needed) |
| Multiple deployments | ✅ Yes | Can roll back to any prior commit |

---

## Part 7: CRT Smoke Tests (Post-Deployment)

After deployment completes, if configured:

### Automatic CRT trigger
Job `trigger-crt-tests` automatically:
1. ✅ Calls CRT GraphQL API to create build
2. ✅ Triggers smoke test suite in CRT
3. ✅ Polls every 30s for completion (up to 60 minutes)
4. ✅ Posts results to PR comment

### CRT Result Summary
**PR comment shows:**
```
╔══════════════════════════════════════════╗
║        CRT Job Execution Summary         ║
╠══════════════════════════════════════════╣
║ PR Number       : #42
║ Workflow Run #  : 987654
║ PR Raiser       : alice-dev
║ PR Approver     : bob-qa
║ Test Build ID   : BUILD-12345
║ Test Result     : passed
╚══════════════════════════════════════════╝
```

### Interpreting results

| Status | Action |
|--------|--------|
| ✅ `passed` | All smoke tests passed → Deployment successful |
| ❌ `failed` | Smoke tests failed → Review test logs → Rollback if critical |
| ⚠️ `error` | CRT job error → Contact CRT admin |
| 🔄 `executing` | Still running → Workflow will wait up to 60 min |

### Manual CRT monitoring
```bash
# View CRT job status
# Copado platform: https://robotic.copado.com/

# Find build by ID from PR comment
# Build ID: BUILD-12345
```

---

## Common Scenarios

### Scenario 1: Coverage drops below threshold
```
❌ Apex coverage 82% is below threshold 85%
```

**Resolution:**
1. Add more test cases to reach 85%
2. Update test classes in PR body if needed
3. Commit & push changes
4. Pipeline re-validates

### Scenario 2: Waiver expired, deployment blocked
```
❌ EXPIRED_WAIVER: ApexDoc - LegacyCode.cls (expires 01-01-2026)
```

**Resolution:**
1. Contact security lead: "Waiver for LegacyCode.cls expired"
2. Lead updates `.github/sf-scanner-waivers.csv` with new expiry
3. Developer pushes update to feature branch
4. Pipeline re-runs and fetches updated waivers

### Scenario 3: Approval >24 hours old
```
⚠️ Approval is more than 24 hours old
```

**Resolution:**
1. Request fresh approval from approver
2. Once approved, pipeline will immediately merge & deploy

### Scenario 4: npm audit finds new vulnerability
```
❌ npm audit: high-severity vulnerabilities found
```

**Resolution:**
1. Run locally: `npm audit`
2. Either:
   - `npm audit fix` if patch available
   - Request npm waiver if no fix available
3. Commit & push
4. Re-run validation

---

## Troubleshooting

### Issue: "PR validation keeps failing"
**Diagnosis:**
```bash
# Check validation job logs
gh run view <run-number> --log

# Download SCA report
gh run download <run-number> --name sfdx-scanner-reports
cat sca-governance-report.csv
```

**Common causes:**
- Expired waiver → Request renewal
- New violation without waiver → Fix or request waiver
- Coverage too low → Add tests

### Issue: "Merge failed"
**Diagnosis:**
```bash
# Check approval-merge-gate job logs
gh run view <run-number> --log
```

**Common causes:**
- Approval >24 hours old → Request re-approval
- Branch protection rules → Resolve conflicts
- Token permissions → Check GH_PAT secret

### Issue: "Deployment timed out"
**Diagnosis:**
```bash
# Check UAT deployment status manually
sfdx org open --target-username uat
# → Setup → Deployments → Deployment Status
```

**Recovery:**
- Wait for deployment to complete, then re-check
- If stuck: contact Salesforce admin or retry deployment

See [troubleshooting.md](troubleshooting.md) for detailed diagnostics.

---

## Approval Workflow Diagram

```
Developer          Reviewer         Deployment       Copado
                                    Approver         (CRT)
   │                  │                 │               │
   ├─ Create PR ─────>│                 │               │
   │                  │                 │               │
   │                  ├─ Code Review ──>│               │
   │                  │                 │               │
   │                  ├─ Request Changes|               │
   │<──── Update ─────┤                 │               │
   │                  │                 │               │
   │                  ├─ Approve ──────>│               │
   │                  │                 │               │
   │                  │                 ├─ Merge ─────>│
   │                  │                 │               │
   │                  │                 ├─ Deploy ────>│
   │                  │                 │               │
   │                  │                 │      ├─ Run Tests
   │                  │                 │<─ Results ───┤
   │                  │                 │               │
   └────────────── UAT Updated ────────────────────────>│
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| Create PR | `gh pr create --base uat --title "PR Title"` |
| Request review | `gh pr edit <n> --add-reviewer @reviewer` |
| Approve PR | `gh pr review <n> --approve` |
| View PR status | `gh pr view <n>` |
| Monitor deployment | `gh run view <n> --log` |
| Trigger rollback | `gh workflow run e2e-uat-pipeline.yml -f action=rollback -f rollback_commit_sha=<sha>` |
| Check coverage | Look for "Apex coverage" in validation job log |
| View SCA report | Download `sfdx-scanner-reports` artifact |

---

## Support

- **Questions?** Comment on PR or contact DevOps channel
- **SCA waivers?** Contact Security Lead
- **CRT issues?** Contact Copado admin
- **Salesforce deployment issues?** Check [troubleshooting.md](troubleshooting.md)
