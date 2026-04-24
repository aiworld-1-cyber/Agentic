# SCA Waiver Management Guide

## Part 1: Salesforce Code Analyzer Waivers

### Schema Reference

**File:** `.github/sf-scanner-waivers.csv` (main branch only)

```csv
rule,file_pattern,message_contains,severity_threshold,expiry,reason,approved_by,approved_date,ticket,status
```

| Column | Type | Required | Description | Example |
|--------|------|----------|-------------|---------|
| `rule` | String | ✅ | Rule name substring match. **Blank or `*` = global component waiver** | `ApexDoc`, `NamingConvention`, `*` |
| `file_pattern` | String | ✅ | Filename substring match. **Blank or `*` = global rule waiver** | `MyClass.cls`, `myLWC`, `/lwc/` |
| `message_contains` | String | ⬜ | Optional: narrow match to violations with this substring in message | `variable unused` |
| `severity_threshold` | Integer | ⬜ | Waive at this severity or above (1-4, blank = any) | `3` |
| `expiry` | Date | ✅ | **Preferred: DD-MM-YYYY** — also accepts DD/MM/YYYY, YYYY-MM-DD | `10-05-2026` |
| `reason` | String | ✅ | Business justification with ticket reference | `Deferred per PROJ-123` |
| `approved_by` | String | ✅ | GitHub username of approver | `jane-techlead` |
| `approved_date` | Date | ✅ | Approval date (any format) | `10-04-2026` |
| `ticket` | String | ✅ | Jira/GitHub issue tracking this waiver | `PROJ-123` |
| `status` | String | ✅ | `ACTIVE` or `REVOKED` (keep revoked for audit) | `ACTIVE` |

### Waiver Types

Determined by `rule` and `file_pattern` wildcards:

#### 1. Specific Waiver
```csv
ApexDoc,MyClass.cls,,3,10-05-2026,Reason,approver,date,PROJ-123,ACTIVE
```
- **Scope:** ApexDoc rule violations in MyClass.cls only
- **Result Label:** `WAIVED`
- **Use:** One-off exceptions for specific violations

#### 2. Global Component Waiver
```csv
*,MyLegacyClass.cls,,3,10-05-2026,Reason,approver,date,PROJ-123,ACTIVE
```
- **Scope:** ALL rules for MyLegacyClass.cls
- **Result Label:** `GLOBAL COMPONENT WAIVER`
- **Use:** Legacy/brownfield components with multiple violations

#### 3. Global Rule Waiver
```csv
ApexDoc,*,,3,10-05-2026,Reason,approver,date,PROJ-123,ACTIVE
```
- **Scope:** ApexDoc rule for ALL files
- **Result Label:** `GLOBAL RULE WAIVER`
- **Use:** Team decision to defer a rule globally (e.g., ApexDoc sprint)

#### 4. Global All Waiver ⚠️
```csv
*,*,,3,10-05-2026,Reason,approver,date,PROJ-123,ACTIVE
```
- **Scope:** ALL rules for ALL files
- **Result Label:** `GLOBAL ALL WAIVER`
- **Use:** Rare — only for initial setup/pilot phases

### Waiver Status Results

Pipeline generates `sca-governance-report.csv` with statuses:

| Status | Icon | Meaning | Action | Fails Pipeline? |
|--------|------|---------|--------|-----------------|
| `WAIVED` | ✅ | Active waiver, >30 days remaining | None | ❌ |
| `WAIVED_EXPIRING_SOON` | ⏰ | Active waiver, ≤30 days remaining | Schedule update | ❌ (warn only) |
| `EXPIRED_WAIVER` | ❌ | Waiver past expiry | **Renew immediately** | ✅ (in `enforce` mode) |
| `VIOLATION` | ⚠️ | No waiver found | Evaluate & waive if approved | ❌ (warn only) |

### How to Create a Waiver

#### Step 1: Identify the violation
```bash
# From pipeline SCA step output
Violation: ApexDoc
File: src/classes/LegacyUtil.cls
Line: 42
Severity: 3 (High)
Message: "Missing comment for public method"
```

#### Step 2: Draft waiver row
```csv
ApexDoc,LegacyUtil.cls,,3,30-06-2026,Refactor scheduled Q3-2026. Tracked in PROJ-456.,john-dev,25-04-2026,PROJ-456,ACTIVE
```

#### Step 3: Add to `.github/sf-scanner-waivers.csv` (main branch)
- Push to feature branch
- Create PR to main
- Get approval from security lead
- Merge to main

#### Step 4: Update main branch reference in PR
- Close & re-open PR to UAT branch
- Pipeline will fetch updated waivers from main

### Governance Policy

#### Who can approve?
- **Team Lead** or **Security Champion**
- **Code Owner** (with additional sign-off)

#### Waiver lifetime:
- **Maximum:** 90 days (force renewal)
- **Recommended:** 30-60 days (review window before expiry)
- **Minimum:** 7 days (only for urgent hotfixes)

#### Audit trail:
- Keep `REVOKED` waivers in CSV (never delete)
- Mark as `REVOKED` when no longer needed
- Include revocation reason in `reason` field

```csv
ApexDoc,OldClass.cls,,3,01-01-2000,REVOKED: Fixed in PROJ-500,john-dev,25-04-2026,PROJ-500,REVOKED
```

#### Escalation paths:
- **Waiver expired → no action:** Violation fails pipeline
- **Too many waivers → ?:** Schedule team review
- **Global waiver → abuse?:** Escalate to architecture review

### Integration with SCA_ENFORCEMENT_MODE

| Mode | Expired Waiver | Global Waivers | Violations | Behavior |
|------|---|---|---|---|
| `enforce` | ❌ FAIL | ✅ Honored | ⚠️ WARN | Production security posture |
| `warn` | ⚠️ WARN | ✅ Honored | ⚠️ WARN | Awareness phase |
| `off` | ⏭️ SKIP | ⏭️ SKIP | ⏭️ SKIP | Disabled |

---

## Part 2: npm Audit Waivers

### Schema Reference

**File:** `.github/sca-waivers.json`

```json
[
  {
    "package": "lodash",
    "severity": "high",
    "advisory": "GHSA-35jh-r3h4-6jhm",
    "reason": "Scheduled for Q2 2026. Tracked in PROJ-500.",
    "expires": "2026-05-30",
    "approved_by": "platform-security"
  }
]
```

| Field | Type | Required | Description | Example |
|-------|------|----------|-------------|---------|
| `package` | String | ✅ | NPM package name | `lodash`, `serialize-javascript` |
| `severity` | String | ✅ | Vulnerability severity | `critical`, `high`, `moderate` |
| `advisory` | String | ✅ | CVE/GHSA advisory ID | `GHSA-35jh-r3h4-6jhm` |
| `reason` | String | ✅ | Business justification | `Mitigation controls in place` |
| `expires` | Date | ✅ | YYYY-MM-DD format | `2026-05-30` |
| `approved_by` | String | ✅ | Approver username/team | `platform-security` |

### npm Audit Check Flow

**Job 3: `sca-sast-stage`** executes:

```bash
npm audit --json --audit-level=high > audit-output.json
```

1. **High/Critical only:** Module-level count
2. **Match against waivers:** Package + severity check
3. **Expiry validation:** Compare today vs `expires`
4. **Status assignment:**
   - ✅ **WAIVED:** Active waiver, not expired
   - ❌ **EXPIRED_WAIVER:** Past expiry (fails in `enforce` mode)
   - ⚠️ **VIOLATION:** No waiver found (warn only, does not fail)

### Waiver Expiry Rules

- Expired waivers **must be renewed** before pipeline passes
- Auto-renewal not supported — manual update required
- Set `expires` conservatively (30-60 days, not 1 year)

### How to Create an npm Waiver

#### Step 1: Run npm audit locally
```bash
npm audit --json > local-audit.json
jq '.vulnerabilities[] | "\(.package): \(.severity)"' local-audit.json
```

#### Step 2: Draft waiver entry
```json
{
  "package": "serialize-javascript",
  "severity": "high",
  "advisory": "GHSA-hhq3-ff89-34mr",
  "reason": "Upgrade path blocked by dependency conflict. Resolved in v2.0.",
  "expires": "2026-06-30",
  "approved_by": "devops-lead"
}
```

#### Step 3: Add to `.github/sca-waivers.json`
```bash
# Validate JSON syntax
jq '.' .github/sca-waivers.json

# Commit and push
git add .github/sca-waivers.json
git commit -m "chore: add npm waiver for serialize-javascript GHSA-hhq3-ff89-34mr"
git push
```

#### Step 4: Verify in pipeline
- Next PR will use updated waivers
- Check `npm-audit-report` artifact for results

### Governance Policy

#### Who approves npm waivers?
- **DevOps Lead** or **Platform Security**
- **Architecture** (for critical severity)

#### Waiver lifetime:
- **High severity:** 30-45 days
- **Moderate severity:** 60-90 days
- **Critical severity:** 14 days (expedited review)

#### Maintenance:
- Review all waivers **monthly**
- Check for expired entries every sprint
- Remove entries when dependency is upgraded

### Troubleshooting npm Audit

#### Issue: "npm audit: No high-severity vulnerabilities"
- **Cause:** Vulnerabilities only in low/moderate
- **Solution:** Lower `--audit-level` flag or add moderate waivers

#### Issue: "Waiver not applied"
- **Cause:** Package name mismatch or JSON syntax error
- **Solution:** `jq '.' .github/sca-waivers.json` to validate; match package name exactly

#### Issue: "Expired waiver still blocking"
- **Cause:** `expires` date is incorrect
- **Solution:** Update `expires` to future date, re-push

---

## Comparison: SCA vs npm Audit

| Aspect | Salesforce SCA | npm Audit |
|--------|---|---|
| **Scope** | Apex, LWC, trigger, pages | JavaScript dependencies only |
| **Trigger** | Changed files only | Package.json changes |
| **Waiver File** | `.github/sf-scanner-waivers.csv` | `.github/sca-waivers.json` |
| **Format** | CSV | JSON |
| **Branch** | Main branch only | Any branch |
| **Wildcards** | `*` for global | N/A |
| **Date Format** | DD-MM-YYYY (flexible) | YYYY-MM-DD (strict) |
| **Failed Waivers** | Fail in `enforce` mode | Fail in `enforce` mode |
| **Renewal Process** | CSV edit + PR to main | JSON edit + commit |

---

## SCA Enforcement Modes Summary

### `enforce` Mode (Production)
```yaml
SCA_ENFORCEMENT_MODE: enforce
```
- ❌ Expired waivers **FAIL** pipeline
- ✅ Valid waivers **PASS** violations
- ⚠️ Unwaived violations **WARN** (do not block)
- 🎯 **Best for:** Mature teams, production deployments

### `warn` Mode (Ramp-up)
```yaml
SCA_ENFORCEMENT_MODE: warn
```
- ⚠️ Expired waivers **WARN** (do not fail)
- ✅ Valid waivers **PASS** violations
- ⚠️ Unwaived violations **WARN** (do not block)
- 🎯 **Best for:** Teams adopting security scanning, building waiver library

### `off` Mode (Disabled)
```yaml
SCA_ENFORCEMENT_MODE: off
```
- ⏭️ All SCA/npm audit steps **SKIPPED**
- No scanning, no waivers checked
- 🎯 **Best for:** Initial setup, non-production repos

---

## Report Outputs

### Salesforce SCA Report
**File:** `sca-governance-report.csv`

```
Status,Rule,File,Line,Severity,Description,Expiry,Days_Left,Reason,Approved_By,Approved_Date,Ticket
WAIVED,ApexDoc,MyClass.cls,42,3,Missing comment,10-05-2026,45,Scheduled refactor,jane-lead,10-04-2026,PROJ-123
VIOLATION,NamingConvention,OldUtil.cls,108,2,Variable naming,,,No waiver,,,
EXPIRED_WAIVER,ApexDoc,LegacyCode.cls,12,3,Missing comment,01-01-2026,-115,Expired,john-dev,01-01-2026,PROJ-999
```

### npm Audit Report
**File:** `audit-output.json`

```json
{
  "vulnerabilities": {
    "serialize-javascript": {
      "name": "serialize-javascript",
      "severity": "high",
      "advisory": "GHSA-hhq3-ff89-34mr"
    }
  }
}
```

---

## Best Practices

1. **Minimal waivers** — Treat as technical debt, not permanent exceptions
2. **Short expiry** — 30-60 days forces active renewal vs. "set and forget"
3. **Link to tickets** — Every waiver must reference a Jira/GitHub issue
4. **Audit monthly** — Review waiver approval history quarterly
5. **Automate renewal** — Set calendar reminders for waiver expirations
6. **Escalate global waivers** — Review global rule/component waivers at sprint planning
7. **SCA_ENFORCEMENT_MODE policy** — Document when/how to transition from `off` → `warn` → `enforce`

---

## Links & References

- [Salesforce Code Analyzer Docs](https://github.com/forcedotcom/sfdx-scanner)
- [npm Audit Docs](https://docs.npmjs.com/cli/v10/commands/npm-audit)
- [GHSA Advisory Database](https://github.com/advisories)
- [CWE/CVSS Severity Definitions](https://nvd.nist.gov/vuln/detail/CVE-2023-12345)
