# Troubleshooting Guide

## Overview

This guide provides diagnosis and remediation steps for common pipeline failures. Failures are organized by job with root cause analysis and solutions.

---

## Job 1: `setup` — Evaluate Scanner Availability

### ❌ Job skipped
**Symptom:** Job shows as skipped in workflow

**Cause:** Triggered by `pull_request_review` (correct behavior — job skips for PR reviews)

**Action:** No action needed — this is expected for pull_request_review events

---

## Job 2: `salesforce-validation` — Salesforce PR Validation

### ❌ "SFDX_AUTH_SECRET_NAME not found"
**Symptom:**
```
Error: Secret '${{ secrets[env.SFDX_AUTH_SECRET_NAME] }}' not found
```

**Diagnosis:**
1. Check environment variable value:
   ```bash
   grep "SFDX_AUTH_SECRET_NAME" .github/workflows/e2e-uat-pipeline.yml
   ```
2. Verify secret exists in GitHub:
   ```bash
   gh secret list
   ```

**Solution:**
- Default is `CRT_UAT_AUTHURL` — create this secret in GitHub
- Or set `SFDX_AUTH_SECRET_NAME` variable to a different secret name
- Ensure secret name matches **exactly** (case-sensitive)

**Create SFDX Auth URL secret:**
```bash
# 1. Generate auth URL
sfdx org login web --alias uat
sfdx org display --targetusername=uat --json | jq -r '.result.sfdxAuthUrl'

# 2. Create secret in GitHub (Settings → Secrets)
gh secret set CRT_UAT_AUTHURL --body "$(sfdx org display --targetusername=uat --json | jq -r '.result.sfdxAuthUrl')"
```

---

### ❌ "org login: INVALID_SFDX_AUTH_URL"
**Symptom:**
```
Error: org login: INVALID_SFDX_AUTH_URL
```

**Cause:**
- Auth URL is expired or malformed
- Auth URL was generated for a different org

**Solution:**
1. Re-generate auth URL:
   ```bash
   # Revoke old auth
   sfdx org logout --username uat --all
   
   # Re-authenticate
   sfdx org login web --alias uat
   
   # Re-create secret
   gh secret set CRT_UAT_AUTHURL --body "$(sfdx org display --targetusername=uat --json | jq -r '.result.sfdxAuthUrl')"
   ```

2. Re-run PR (push any commit):
   ```bash
   git commit --allow-empty -m "retry: auth url update"
   git push
   ```

---

### ❌ "Apex coverage 82% is below threshold 85%"
**Symptom:**
```
Coverage check failed: 82% < threshold 85%
```

**Cause:** Test code doesn't cover sufficient code lines

**Solution:**
1. **Add more test cases:**
   ```apex
   @isTest
   public class MyFeatureTest {
     @isTest
     public static void testNewBehavior() {
       // Test new feature
       MyFeature mf = new MyFeature();
       mf.execute();
       System.assert(mf.isSuccess());
     }
   }
   ```

2. **Update `COVERAGE_THRESHOLD` variable** (if threshold too high):
   ```bash
   # In GitHub UI → Settings → Variables
   # Update COVERAGE_THRESHOLD to lower value (e.g., 80)
   ```

3. **Use `--test-level RunSpecifiedTests` in PR:**
   - Pipeline automatically infers test classes by suffix
   - Or add `Tests: TestClass1, TestClass2` in PR body

4. **Push changes and re-run:**
   ```bash
   git add .
   git commit -m "test: add test cases for new feature"
   git push
   ```

---

### ❌ "No delta detected" or "❌ has_delta = false"
**Symptom:**
```
has_delta output: false
```

**Cause:**
- No Salesforce source changes (changes in other files only)
- `package.xml` has no `<members>` tags

**Action:**
- **If documentation-only PR:** Normal — validation skipped, but approval still required
- **If Apex should change:** Check that files were committed to correct directory (`force-app/main/default/classes/`)

**Verify:**
```bash
# Check what files changed
git diff --name-only origin/uat HEAD

# Verify Salesforce files are in expected path
find force-app/main/default -name '*.cls' -o -name '*.js'
```

---

### ❌ "Deploy validation failed"
**Symptom:**
```
Error: sf project deploy validate --async failed
```

**Cause:**
- Syntax error in Apex code
- Deployment conflict (same file edited in main + feature branch)
- Missing dependencies

**Solution:**
1. **Check validation error details:**
   ```bash
   # View full error in workflow logs
   gh run view <run-number> --log | grep -A 10 "Deploy validation"
   ```

2. **Fix issues locally:**
   ```bash
   # Validate locally
   sf project validate deploy --source-dir force-app/main/default
   
   # Fix errors
   # ...
   
   # Commit and push
   git add .
   git commit -m "fix: deployment validation errors"
   git push
   ```

3. **Resolve conflicts with main:**
   ```bash
   git fetch origin
   git merge origin/uat
   # Resolve conflicts
   git add .
   git commit -m "merge: resolve conflicts with uat"
   git push
   ```

---

### ❌ "SCA report not found" or SCA step skipped
**Symptom:**
```
sfdx-report.csv not found
```

**Cause:**
- `SCA_ENFORCEMENT_MODE` set to `off`
- No source files to scan (no delta)

**Solution:**
1. **Check SCA_ENFORCEMENT_MODE:**
   ```bash
   # GitHub UI → Settings → Variables → SCA_ENFORCEMENT_MODE
   # Must be 'enforce', 'warn', or 'off'
   ```

2. **If intentionally `off` (initial setup):** No action needed
3. **If should be scanning:**
   ```bash
   # Update variable to 'enforce' or 'warn'
   gh variable set SCA_ENFORCEMENT_MODE --body "enforce"
   ```

4. **Re-run PR:**
   ```bash
   git commit --allow-empty -m "retry: enable SCA"
   git push
   ```

---

### ❌ "EXPIRED_WAIVER: ApexDoc"
**Symptom:**
```
Status: EXPIRED_WAIVER
Rule: ApexDoc
File: MyClass.cls
Expiry: 01-01-2026
Days_Left: -115
```

**Cause:** Waiver expiration date has passed

**Solution:**
1. **Contact Security Lead:**
   - Email: "ApexDoc waiver for MyClass.cls expired"
   - Request: "Please renew waiver to [target date]"

2. **Security Lead updates waiver:**
   ```bash
   # Edit .github/sf-scanner-waivers.csv on main
   # Update expiry date
   git add .github/sf-scanner-waivers.csv
   git commit -m "chore: renew ApexDoc waiver for MyClass.cls"
   git push origin main
   ```

3. **Developer re-triggers validation:**
   ```bash
   git commit --allow-empty -m "retry: fetch updated waivers"
   git push
   ```

4. **Pipeline fetches updated waivers from main** → Violation now marked `WAIVED`

---

### ❌ "Waiver file tampering detected"
**Symptom:**
```
⚠️ Warning: .github/sf-scanner-waivers.csv was modified in this PR
```

**Cause:** Developer modified waiver file in PR (not allowed — main branch only)

**Solution:**
1. **Revert waiver file changes:**
   ```bash
   git checkout origin/uat -- .github/sf-scanner-waivers.csv
   git add .github/sf-scanner-waivers.csv
   git commit -m "revert: waiver file managed on main branch only"
   git push
   ```

2. **Request waiver on main branch:**
   - Contact security lead with waiver request
   - Security lead adds to main branch via separate PR

---

### ❌ "Could not fetch waivers — continuing without waivers"
**Symptom:**
```
⚠️ Could not fetch waivers - continuing without waivers
```

**Cause:**
- GitHub API token missing or invalid permissions
- Waiver file doesn't exist on main branch (first time setup)

**Solution:**
1. **Verify GH_PAT secret:**
   ```bash
   # Check token has correct permissions
   # GitHub UI → Settings → Developer settings → Fine-grained tokens
   # Required: actions:read, variables:read
   ```

2. **Create waiver file on main branch:**
   ```bash
   # If this is first setup, create .github/sf-scanner-waivers.csv on main
   git checkout main
   cat > .github/sf-scanner-waivers.csv << 'EOF'
   rule,file_pattern,message_contains,severity_threshold,expiry,reason,approved_by,approved_date,ticket,status
   EOF
   git add .github/sf-scanner-waivers.csv
   git commit -m "chore: initialize SCA waivers file"
   git push
   ```

3. **Re-trigger validation:**
   ```bash
   git commit --allow-empty -m "retry: fetch waivers"
   git push
   ```

---

### ❌ "no-delta-pkg" or package.xml empty
**Symptom:**
```
has_delta_pkg=false
```

**Cause:**
- `sfdx-git-delta` failed or produced empty package
- `DELTA_FROM_COMMIT` is incorrect or doesn't exist

**Solution:**
1. **Verify DELTA_FROM_COMMIT variable:**
   ```bash
   # Check current value
   gh variable list | grep DELTA_FROM_COMMIT
   
   # Verify commit exists
   git log --oneline | grep <DELTA_FROM_COMMIT>
   ```

2. **Reset to current main:**
   ```bash
   # Get current main SHA
   git rev-parse origin/main
   
   # Update variable
   gh variable set DELTA_FROM_COMMIT --body "$(git rev-parse origin/main)"
   ```

3. **Verify delta calculation:**
   ```bash
   # Run locally
   npm install -g sfdx-git-delta
   sgd --repo . --from $(git rev-parse origin/main) --to HEAD --output delta_pkg
   ls delta_pkg/
   ```

---

## Job 3: `sca-sast-stage` — SCA/SAST Stage (npm Audit)

### ❌ "npm install failed"
**Symptom:**
```
Error: npm ERR! code ERESOLVE
```

**Cause:**
- Conflicting package versions
- Corrupted node_modules

**Solution:**
1. **Clean and reinstall locally:**
   ```bash
   rm -rf node_modules package-lock.json
   npm install
   npm audit
   ```

2. **Fix compatibility issues:**
   ```bash
   npm update --save
   ```

3. **Commit and push:**
   ```bash
   git add package.json package-lock.json
   git commit -m "fix: resolve npm dependencies"
   git push
   ```

---

### ❌ "npm audit: high-severity vulnerabilities"
**Symptom:**
```
Found 3 vulnerabilities (1 high, 2 moderate)
```

**Cause:**
- New vulnerability discovered in dependency
- No patch available yet

**Solution:**

**Option A: Auto-fix (if available):**
```bash
npm audit fix
git add package.json package-lock.json
git commit -m "fix: npm audit --fix"
git push
```

**Option B: Request waiver (if no fix):**
1. **Identify vulnerable package:**
   ```bash
   npm audit --json | jq '.vulnerabilities'
   ```

2. **Create waiver in `.github/sca-waivers.json`:**
   ```json
   {
     "package": "serialize-javascript",
     "severity": "high",
     "advisory": "GHSA-hhq3-ff89-34mr",
     "reason": "No fix available yet. Mitigation controls in place.",
     "expires": "2026-06-30",
     "approved_by": "platform-security"
   }
   ```

3. **Commit and push:**
   ```bash
   git add .github/sca-waivers.json
   git commit -m "chore: add npm audit waiver for serialize-javascript"
   git push
   ```

---

### ❌ "Expired npm audit waiver"
**Symptom:**
```
❌ Expired waiver for lodash (high)
```

**Cause:** Waiver expiry date passed

**Solution:**
1. **Update `.github/sca-waivers.json`:**
   ```json
   {
     "package": "lodash",
     "severity": "high",
     "advisory": "GHSA-35jh-r3h4-6jhm",
     "reason": "Scheduled for Q2 2026 upgrade",
     "expires": "2026-06-30",
     "approved_by": "dev-lead"
   }
   ```

2. **Commit and push:**
   ```bash
   git add .github/sca-waivers.json
   git commit -m "chore: renew npm audit waiver for lodash"
   git push
   ```

---

## Job 4: `automated-governance` — Automated Hard Gates

### ❌ Job skipped / "No delta detected"
**Symptom:** Job shows as skipped

**Cause:** PR has no Salesforce source changes

**Action:** Normal — documentation-only PRs skip this. Approval still required.

---

## Job 5 & 6: `checkmarx-sast` / `fortify-sast-dast`

### ⏭️ Job skipped
**Symptom:** One or both jobs show skipped

**Cause:**
- Secret not configured:
  - CheckMarx: `CX_CLIENT_SECRET` not set → Job skipped
  - Fortify: `FOD_CLIENT_SECRET` not set → Job skipped

**Solution:**
- If intentional (not using scanners): No action needed
- If should be active: Contact security admin to create secrets

---

## Job 7: `approval-merge-gate` — Approval & Merge Gate

### ❌ "pull_request_review event not triggered"
**Symptom:** Job doesn't run even after submitting approval

**Cause:**
- GitHub event not triggered (local testing)
- Workflow event filter incorrect

**Action:**
- Ensure PR is created in GitHub UI (not local test)
- Click "Approve" button in GitHub PR review UI

---

### ❌ "Approval is more than 24 hours old"
**Symptom:**
```
⚠️ Approval is more than 24 hours old
```

**Cause:** PR approved >24 hours ago, merge time needs fresh approval

**Solution:**
1. **Request fresh approval:**
   ```bash
   gh pr review <pr-number> --approve \
     --body "Re-approval for deployment (prior approval >24h old)"
   ```

2. **Deployment will proceed** after fresh approval submitted

---

### ❌ "Merge failed: branch protection"
**Symptom:**
```
Error: 403 - branch protection violation
```

**Cause:**
- Required status checks failing
- Conflicts with main branch

**Solution:**
1. **Verify all checks pass:**
   ```bash
   gh pr view <pr-number> --json statusCheckRollup
   ```

2. **If checks failing:** Fix issues and update PR
3. **If conflicts:** Resolve merge conflicts:
   ```bash
   git fetch origin
   git merge origin/uat
   # Resolve conflicts
   git add .
   git commit -m "merge: resolve conflicts"
   git push
   ```

4. **Request fresh approval** after fixes

---

## Job 8: `deploy-after-merge` — Deploy to UAT

### ❌ "Deploy failed: insufficient privileges"
**Symptom:**
```
Error: INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
```

**Cause:** SFDX auth user missing permissions in UAT org

**Solution:**
1. **Verify user permissions in UAT:**
   - Login to UAT org
   - Setup → Users → Edit auth user
   - Ensure user has permission set: "Salesforce Admin"

2. **Re-generate auth URL:**
   ```bash
   sfdx org logout --username uat --all
   sfdx org login web --alias uat
   gh secret set CRT_UAT_AUTHURL --body "$(sfdx org display --targetusername=uat --json | jq -r '.result.sfdxAuthUrl')"
   ```

3. **Trigger re-deployment:**
   - Re-open PR to uat branch (this triggers new approval cycle)
   - Or manually trigger workflow_dispatch with `action=deploy`

---

### ❌ "Deploy timed out" or "Polling exceeded max attempts"
**Symptom:**
```
Max polling attempts (240) exceeded
```

**Cause:**
- Deployment taking >4 hours (max poll time)
- Salesforce org issues

**Solution:**
1. **Check deployment status manually:**
   ```bash
   # In Salesforce org
   sfdx org open --target-username uat
   # → Setup → Deployments → Deployment Status
   
   # Or via CLI
   sf project deploy report --job-id <deploy-id> --json
   ```

2. **If deployment completed:**
   - Verify components in org (Setup → Installed Packages, etc.)
   - Deployment successful despite timeout

3. **If deployment still running:**
   - Wait for it to complete manually
   - Check org logs for issues

4. **If deployment failed:**
   - Review failure details
   - Rollback if needed:
     ```bash
     gh workflow run e2e-uat-pipeline.yml -f action=rollback -f rollback_commit_sha=<prior-sha>
     ```

---

### ❌ "DELTA_FROM_COMMIT update failed"
**Symptom:**
```
Error: 401 - GitHub API authentication failed
```

**Cause:** `GH_PAT` secret invalid or missing permissions

**Solution:**
1. **Verify GH_PAT permissions:**
   - GitHub UI → Settings → Developer settings → Fine-grained tokens
   - Required scope: `variables:read/write`

2. **Regenerate token:**
   ```bash
   # Create new fine-grained PAT
   # Scopes: actions:read, contents:read, variables:read/write
   # Copy token
   
   # Update secret
   gh secret set GH_PAT --body "<new-token>"
   ```

3. **Re-trigger deployment:**
   - Re-open PR to uat
   - Or trigger via workflow_dispatch

---

## Job 9: `trigger-crt-tests` — CRT Smoke Tests

### ❌ "CRT API authentication failed"
**Symptom:**
```
Error: 401 - Unauthorized (GraphQL API)
```

**Cause:** `CRT_API_TOKEN` invalid or expired

**Solution:**
1. **Regenerate CRT token:**
   - Contact Copado admin
   - Request new API token
   - Update GitHub secret:
     ```bash
     gh secret set CRT_API_TOKEN --body "<new-token>"
     ```

2. **Re-trigger build:**
   - Re-submit approval on PR
   - Deployment will automatically trigger CRT tests

---

### ❌ "CRT build not found in latestBuilds"
**Symptom:**
```
Warning: CRT build not found in latest results
```

**Cause:**
- Build ID mismatch
- CRT project/job/org IDs incorrect

**Solution:**
1. **Verify CRT variables:**
   ```bash
   gh variable list | grep CRT_
   ```

   Should show:
   - `CRT_JOB_ID` (default: 115686)
   - `CRT_PROJECT_ID` (default: 73283)
   - `CRT_ORG_ID` (default: 43532)

2. **Update if incorrect:**
   ```bash
   gh variable set CRT_PROJECT_ID --body "<correct-id>"
   gh variable set CRT_JOB_ID --body "<correct-id>"
   gh variable set CRT_ORG_ID --body "<correct-id>"
   ```

3. **Re-trigger deployment:**
   - Re-submit PR approval

---

### ❌ "CRT test results: failed"
**Symptom:**
```
Test Result: failed
```

**Cause:**
- Smoke test failed (bug in deployment)
- Incorrect test data

**Action:**
1. **Review CRT test logs:**
   - Copado platform: https://robotic.copado.com
   - Build ID: [from PR comment]

2. **Identify failure cause:**
   - Functional issue in code → Fix & redeploy
   - Test data issue → Contact CRT admin

3. **Rollback if critical:**
   ```bash
   gh workflow run e2e-uat-pipeline.yml \
     -f action=rollback \
     -f rollback_commit_sha=<prior-sha>
   ```

---

## Job 10: `rollback` — Rollback Deployment

### ❌ "Rollback deployment failed"
**Symptom:**
```
Rollback deployment failed
```

**Cause:**
- Target SHA doesn't exist
- Rollback package corrupt

**Solution:**
1. **Verify target SHA:**
   ```bash
   git log --oneline -20
   git cat-file -t <sha>  # Should print 'commit'
   ```

2. **Retry with correct SHA:**
   ```bash
   gh workflow run e2e-uat-pipeline.yml \
     -f action=rollback \
     -f rollback_commit_sha=<correct-sha>
   ```

3. **Manual rollback (if all else fails):**
   ```bash
   sfdx org open --target-username uat
   # → Setup → Deployments → Deploy Related Items
   # → Revert package manually
   ```

---

### ❌ "Cannot rollback data changes"
**Symptom:**
```
Metadata rolled back, but data changes remain
```

**Cause:** Rollback only reverts metadata, not data modifications

**Solution:**
1. **If data was modified incorrectly:**
   - Contact Salesforce admin
   - Request data restore from backup (if available)

2. **In future, consider:**
   - Using sandboxes for testing
   - UAT data refresh process
   - Separate data/metadata deployments

---

## General Troubleshooting

### How to view workflow logs
```bash
# List recent runs
gh run list -w e2e-uat-pipeline.yml

# View specific run logs
gh run view <run-number> --log

# View specific job logs
gh run view <run-number> --log | grep -A 20 "Job Name"
```

### How to download artifacts
```bash
# List artifacts
gh run download <run-number> --list

# Download specific artifact
gh run download <run-number> --name sfdx-scanner-reports

# Inspect CSV
head -20 sca-governance-report.csv
```

### How to re-run a failed job
```bash
# Re-run all failed jobs in workflow
gh run rerun <run-number> --failed

# Or re-trigger by updating PR
git commit --allow-empty -m "retry: re-run pipeline"
git push
```

### Debug commands
```bash
# Test SFDX auth
sfdx org list

# Test npm setup
npm list
npm audit

# Test git delta
npm install -g sfdx-git-delta
sgd --help

# Validate YAML
yamllint .github/workflows/e2e-uat-pipeline.yml
```

---

## Emergency Contacts

| Role | Escalation Path |
|------|---|
| **DevOps** | #devops-oncall Slack channel |
| **Security** | #platform-security Slack channel |
| **Salesforce Admin** | salesforce-admins@company.com |
| **CRT/Copado** | copado-support@company.com |

---

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Salesforce CLI Troubleshooting](https://developer.salesforce.com/docs/cli/troubleshooting)
- [npm audit Documentation](https://docs.npmjs.com/cli/v10/commands/npm-audit)
- [sfdx-git-delta GitHub](https://github.com/sfdx-git-delta/sfdx-git-delta)
- [Copado Documentation](https://copado.atlassian.net/wiki)
