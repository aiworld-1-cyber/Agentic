# Troubleshooting Guide

Diagnosis and fixes for common pipeline failures.

---

## Job: salesforce-validation

### Error: "Validation failed: Apex test coverage (XX% < 85%)"

**Cause:** Code changes require new tests, or existing tests don't cover changed code.

**Diagnosis:**
```bash
# Run tests locally
sf apex test run --code-coverage-only --wait 60
# Check coverage report
```

**Fix:**
1. Write tests for uncovered code
2. Ensure `*Test` suffix classes are included in test run
3. If threshold is unreasonable, adjust `COVERAGE_THRESHOLD` variable
4. Commit tests, push to PR

---

### Error: "Deploy validate failed: Metadata error"

**Cause:** Syntax error, missing dependency, or API compatibility issue.

**Diagnosis:**
1. Check **Actions → Deploy Details** for specific error message
2. Download **delta artifact** to inspect changed files
3. Test locally:
   ```bash
   sf project deploy validate --manifest delta_package/package.xml --source-dir delta_package
   ```

**Fix:**
- Fix syntax errors in changed code
- Add missing metadata dependencies (e.g., custom fields before reports)
- Verify API versions match target org
- Commit fix, push to PR

---

### Error: "No authentication org found"

**Cause:** Secret `CRT_UAT_AUTHURL` is missing, corrupted, or wrong org.

**Diagnosis:**
```bash
# Verify secret exists
gh secret list

# Verify format (should start with force:// or similar)
gh secret view CRT_UAT_AUTHURL
```

**Fix:**
1. Go to **Settings → Secrets and variables → Actions**
2. Delete `CRT_UAT_AUTHURL`
3. Generate new auth URL:
   ```bash
   sf org login sfdx-url --sfdx-url-input <value> --alias uat --set-default
   sf org login sfdx-url display --json | jq -r '.result.sfdxAuthUrl'
   # Copy full output
   ```
4. Create secret with full URL
5. Re-run failed workflow

---

### Error: "EXPIRED_WAIVER [ApexDoc] MyClass.cls"

**Cause:** SCA waiver has past expiry date.

**Diagnosis:**
Check `.github/sf-scanner-waivers.csv` for rule+file combo with past expiry date.

**Fix (Option A — Fix the violation):**
1. Fix the code violation (add documentation, reduce complexity, etc.)
2. Commit, push to PR

**Fix (Option B — Renew waiver):**
1. Update `.github/sf-scanner-waivers.csv` on main branch
2. Change `expiry` to future date
3. Update `approved_date`, `approved_by`
4. Commit, merge PR to main
5. Re-run validation on original PR

**Bypass temporarily:**
```bash
# Emergency only: Set SCA_ENFORCEMENT_MODE to "warn"
# Settings → Variables → SCA_ENFORCEMENT_MODE = "warn"
# Reset to "enforce" after emergency resolves
```

---

### Error: "Delta package empty"

**Cause:** No changes detected between branches.

**Expected behavior:** Pipeline still runs but skips deploy/test steps.

**Fix:** Not an error — ensure changes are in `force-app/**` monitored paths.

---

## Job: sca-sast-stage

### Error: "UNWAIVED [high] lodash"

**Cause:** npm high/critical vulnerability with no waiver.

**Diagnosis:**
```bash
npm audit --json | jq '.vulnerabilities | keys'
# Check which package is vulnerable
```

**Fix (Option A — Upgrade):**
```bash
npm update lodash --save
npm audit fix
git commit -am "npm: upgrade lodash to fix GHSA-xxxx"
```

**Fix (Option B — Add waiver):**
1. Edit `.github/sca-waivers.json`
2. Add entry:
   ```json
   {
     "package": "lodash",
     "severity": "high",
     "advisory": "GHSA-xxxx-xxxx-xxxx",
     "reason": "No fix available — scheduled for removal Q3.",
     "expires": "2026-06-30",
     "approved_by": "platform-security"
   }
   ```
3. Merge PR to main
4. Re-run validation on original PR

---

### Error: "No waiver file found"

**Cause:** `.github/sca-waivers.json` doesn't exist (expected on first run).

**Fix:**
- Not an error — all vulnerabilities evaluated without waivers
- Create `.github/sca-waivers.json` on main branch with empty array:
  ```json
  []
  ```
- Or add waiver entries as violations are found

---

## Job: automated-governance

### Error: "Test execution failed"

**Cause:** Tests failing or hanging.

**Diagnosis:**
Check Actions log for test class name and error.

**Fix:**
1. Run test locally:
   ```bash
   sf apex test run --test-level RunLocalTests --wait 60
   ```
2. Fix failing tests
3. Commit, push to PR

---

## Job: approval-merge-gate

### Error: "Approval is older than 24 hours"

**Cause:** PR was approved >24 hours ago.

**Fix:**
1. **Re-approve PR** (same reviewer or new reviewer):
   - Go to PR → Review changes → Approve
2. Merge gate will accept new approval
3. Deployment proceeds

---

### Error: "Merge conflict — cannot merge"

**Cause:** UAT branch has changes that conflict with PR.

**Fix:**
1. Checkout PR branch locally:
   ```bash
   git fetch origin pull/<PR_ID>/head:<branch-name>
   git checkout <branch-name>
   ```
2. Rebase on latest uat:
   ```bash
   git fetch origin uat
   git rebase origin/uat
   # Resolve conflicts
   git add .
   git rebase --continue
   ```
3. Force-push to PR:
   ```bash
   git push --force-with-lease origin <branch-name>
   ```
4. Re-approve and merge

---

## Job: deploy-after-merge

### Error: "Deployment failed: Code coverage below threshold"

**Cause:** Deployed code doesn't meet coverage requirement.

**Diagnosis:**
```bash
# Check org coverage
sf apex test report
```

**Fix:**
1. Write tests for uncovered code
2. Deploy tests (may need separate deployment)
3. Rerun smoketest

---

### Error: "Could not build delta package — git merge base not found"

**Cause:** Shallow clone (GitHub runner) with no DELTA_FROM_COMMIT variable.

**Diagnosis:**
Check Actions log for `merge_base` calculation.

**Fix:**
1. Ensure `DELTA_FROM_COMMIT` variable is set:
   ```bash
   gh variable list
   ```
2. If missing, set it:
   ```bash
   git log uat --oneline | head -1  # Get latest commit
   gh variable set DELTA_FROM_COMMIT --body <commit-sha>
   ```
3. Re-run workflow

---

### Error: "Deployment timed out (>60 min)"

**Cause:** Large deployment or org performance issue.

**Diagnosis:**
Check org for long-running jobs, locks, or batch apex.

**Fix:**
1. Check org health:
   ```bash
   sf org open --alias uat
   # Check Setup → Monitoring → Apex Jobs
   ```
2. Kill long-running jobs if safe
3. Retry deployment:
   - Go to Actions → deploy-after-merge → Re-run job

---

## Job: trigger-crt-tests

### Error: "Failed to trigger CRT build"

**Cause:** API token invalid, project/job IDs incorrect, or CRT service down.

**Diagnosis:**
Check error response in Actions log for GraphQL error details.

**Fix:**
1. Verify `CRT_API_TOKEN` secret is valid:
   - Log into CRT portal
   - Regenerate token if expired
   - Update secret in GitHub
2. Verify variables:
   - `CRT_PROJECT_ID` (default: 73283)
   - `CRT_JOB_ID` (default: 115686)
   - `CRT_ORG_ID` (default: 43532)
3. Check CRT service status
4. Re-run job

---

### Error: "CRT tests failed with status: failed"

**Cause:** Smoke tests detected regressions in deployed code.

**Diagnosis:**
Click CRT dashboard link in PR comment to view test logs.

**Fix:**
1. Review CRT test results
2. Identify failing test case
3. Fix deployed code
4. **Rollback** deployment:
   ```bash
   # See docs/manual_runbook.md for rollback procedure
   ```
5. Create hot-fix PR with corrected code
6. Re-deploy

---

### Error: "CRT status: error or cancelled"

**Cause:** CRT execution environment issue or job cancelled.

**Diagnosis:**
Check CRT dashboard for build logs.

**Fix:**
1. Verify CRT environment health
2. Retry test run:
   - Go to CRT dashboard → Re-run build
   - Or: Actions → trigger-crt-tests → Re-run job

---

## Job: rollback

### Error: "Could not build reverse delta"

**Cause:** Commit SHA invalid or doesn't exist in history.

**Diagnosis:**
Verify commit SHA:
```bash
git log --oneline | grep <rollback_commit_sha>
```

**Fix:**
1. Find correct commit SHA:
   ```bash
   git log uat --oneline -50
   ```
2. Trigger rollback with correct SHA via workflow_dispatch

---

### Error: "Rollback deployment failed"

**Cause:** Metadata dependency issue or org constraint.

**Diagnosis:**
Check deployment error in Actions log.

**Fix:**
1. Manually verify org state matches expected rollback
2. Check for locks or in-progress deployments:
   ```bash
   sf org open --alias uat
   # Setup → Monitoring → Deployment Status
   ```
3. Resolve org issues (unlock fields, cancel jobs, etc.)
4. Retry rollback

---

## General Troubleshooting

### Workflow Not Triggering

**Cause:** PR doesn't meet trigger conditions.

**Diagnosis:**
- PR not targeting `uat` branch?
- Changes not in monitored paths (`force-app/**`, `.github/workflows/`)?
- PR is draft?

**Fix:**
1. Check PR: Base branch = `uat`?
2. Verify changes touch monitored paths
3. Mark PR as ready (if draft)
4. Push empty commit to re-trigger:
   ```bash
   git commit --allow-empty -m "Trigger workflow"
   git push
   ```

---

### Workflow Hangs / Timeout

**Cause:** Long-running step without output.

**Diagnosis:**
Check Actions logs for last output timestamp.

**Fix:**
1. Increase timeout in relevant step (if code change available)
2. Or: Cancel workflow, investigate root cause
3. Common causes:
   - Slow Salesforce org
   - Network timeout
   - Deadlock in batch apex

---

### Secret Not Found Error

**Cause:** Secret name typo or not created.

**Diagnosis:**
```bash
gh secret list
# Check if secret exists with correct name
```

**Fix:**
1. Verify secret name matches workflow reference
2. If missing, create it:
   ```bash
   gh secret set SECRET_NAME --body "value"
   ```
3. Secrets are case-sensitive

---

### Artifact Download Issues

**Artifacts** are stored for 30 days by default. If older:

1. Go to **Actions** → workflow run
2. Click **Artifacts** section
3. If empty, artifact expired or run never uploaded
4. To extend retention, edit `.github/workflows/e2e-uat-pipeline.yml`:
   ```yaml
   - uses: actions/upload-artifact@v4
     with:
       retention-days: 90  # Increase from 30
   ```

---

## Quick Reference: Common Fixes

| Issue | Quickfix |
|-------|----------|
| Tests failing | `sf apex test run --code-coverage-only --wait 60` |
| Coverage too low | Write tests, ensure `*Test` suffix |
| Expired waiver | Renew expiry date in `.github/sf-scanner-waivers.csv` |
| npm vulnerability | `npm update <package>` or add waiver |
| Merge conflict | `git rebase origin/uat` locally, resolve, force-push |
| Old approval | Re-approve PR |
| Deployment timeout | Check org health, retry |
| CRT failure | Check CRT dashboard, rollback if regression |
| Rollback needed | Find commit SHA, trigger workflow_dispatch |

---

## Escalation

If issue persists after troubleshooting:

1. **Gather info:**
   - Actions run link
   - Full error message (screenshot/paste)
   - Reproduction steps

2. **Contact:**
   - Salesforce admin (org issues)
   - DevOps/CI-CD team (pipeline issues)
   - CRT support (test issues)

3. **Interim:** Use `SCA_ENFORCEMENT_MODE=warn` to unblock (temporary only)

---

## Links

- [Pipeline Setup](pipeline-setup.md)
- [Manual Runbook](manual_runbook.md)
- [SCA Waivers](sca-waivers.md)
