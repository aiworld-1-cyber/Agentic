# Static Code Analysis (SCA) Waivers

This document covers both Salesforce Code Analyzer (Apex/LWC) and npm package vulnerability waivers.

---

## Part 1: Salesforce Code Analyzer Waivers

### Overview

File: `.github/sf-scanner-waivers.csv` (stored on **main branch** only — PR modifications are ignored)

The pipeline **always fetches waivers from the main branch** via GitHub API during PR validation. This prevents developers from waiving violations locally.

---

### CSV Schema

```csv
rule,file_pattern,message_contains,severity_threshold,expiry,reason,approved_by,approved_date,ticket,status
```

| Column | Required | Description |
|--------|----------|-------------|
| `rule` | ✅ | Rule name substring match. Examples: `ApexDoc`, `no-unused-vars`, `DepthOfExecution`. Use `*` or leave blank for global component waiver. |
| `file_pattern` | ✅ | Filename or path substring match. Examples: `MyClass.cls`, `myLWC`, `/lwc/`. Use `*` or leave blank for global rule waiver. |
| `message_contains` | ⬜ | Optional substring of violation message to narrow match. Leave blank to match all messages for this rule+file combo. |
| `severity_threshold` | ⬜ | Only waive at this severity or above (3=high, 4=critical). Leave blank to waive any severity. |
| `expiry` | ✅ | Waiver expiration date. Formats: `DD-MM-YYYY` (preferred), `DD/MM/YYYY`, or `YYYY-MM-DD`. |
| `reason` | ✅ | Business justification with Jira reference (e.g., "Refactor planned in Q3 — tracked in PROJ-456"). |
| `approved_by` | ✅ | GitHub username of approver. |
| `approved_date` | ✅ | Approval date (any format — used for audit only). |
| `ticket` | ✅ | Jira/GitHub issue ID for tracking. |
| `status` | ✅ | `ACTIVE` or `REVOKED`. Keep revoked rows for audit trail — never delete. |

---

### Waiver Types

Determined by `rule` and `file_pattern` combinations:

#### 1. Specific Waiver
**rule:** `ApexDoc` | **file_pattern:** `MyClass.cls`
- Waives `ApexDoc` violations **only in `MyClass.cls`**
- Log label: `WAIVED`

#### 2. Global Component Waiver
**rule:** `*` or blank | **file_pattern:** `MyClass.cls`
- Waives **ALL rules** for `MyClass.cls`
- Log label: `GLOBAL COMPONENT WAIVER`
- Use case: Legacy file undergoing full rewrite

#### 3. Global Rule Waiver
**rule:** `ApexDoc` | **file_pattern:** `*` or blank
- Waives `ApexDoc` **for ALL files**
- Log label: `GLOBAL RULE WAIVER`
- Use case: ApexDoc deferred org-wide for sprint

#### 4. Global All Waiver ⚠️
**rule:** `*` or blank | **file_pattern:** `*` or blank
- Waives **ALL rules for ALL files**
- Log label: `GLOBAL ALL WAIVER`
- **Use sparingly** — defeats purpose of scanning

---

### Status Values & Interpretation

| Status | Result | Days Left | Action |
|--------|--------|-----------|--------|
| `WAIVED` ✅ | Active, >30 days remaining | >30 | Violation allowed; no pipeline impact |
| `WAIVED_EXPIRING_SOON` ⏰ | Active, ≤30 days remaining | 1–30 | Warning in logs; violation still allowed |
| `VIOLATION` ⚠️ | No waiver found | — | Warning in logs; does NOT fail pipeline |
| `EXPIRED_WAIVER` ❌ | Past expiry date | 0 or negative | **Fails pipeline** (unless `SCA_ENFORCEMENT_MODE=warn`) |

---

### Example Waivers

```csv
rule,file_pattern,message_contains,severity_threshold,expiry,reason,approved_by,approved_date,ticket,status
# Specific: Waive ApexDoc for MyClass.cls only
ApexDoc,MyClass.cls,,3,30-06-2026,Class rewrite in progress.,alice-lead,01-01-2026,PROJ-123,ACTIVE

# Global Component: Waive ALL rules for legacy code
*,LegacyController.cls,,3,31-05-2026,EOL migration in progress. Full replacement by Q3.,bob-arch,15-12-2025,PROJ-456,ACTIVE

# Global Rule: Waive DepthOfExecution across all code
DepthOfExecution,*,,3,31-08-2026,Complex domain model. Refactor scheduled for next phase.,charlie-tech,01-01-2026,PROJ-789,ACTIVE

# Specific + message filter: Only waive EXACT message
UnusedVariable,CalculationEngine.cls,temp variable in loop,3,30-04-2026,Benchmarking code — remove in prod.,dave-perf,10-02-2026,PROJ-999,ACTIVE

# Revoked: Keep for audit trail
no-unused-vars,/aura/,,,30-09-2025,DEPRECATED — ESLint upgraded in v2.,eve-qa,01-09-2025,PROJ-111,REVOKED
```

---

### Governance Rules

1. **Expiration Policy:** Waivers expire after set date. Expired waivers:
   - Logged as `EXPIRED_WAIVER` ❌
   - **Fail the pipeline** (in `enforce` mode)
   - Should trigger developer action to fix or renew

2. **Approval Required:** All new/renewed waivers require:
   - Tech lead sign-off (`approved_by`)
   - Jira ticket reference
   - Business justification in `reason`

3. **Audit Trail:** Keep `REVOKED` rows in the CSV
   - Provides history of deprecated waivers
   - Helps identify patterns (e.g., "all ApexDoc waivers revoked in 2026 = rule no longer needed")

4. **Who Updates:** GitHub team with push access to main branch
   - Create PR with waiver changes
   - PR reviewers = approval signatories
   - Merge to main = effective immediately

---

### Pipeline Validation Report

File: `sca-governance-report.csv` (uploaded as artifact after SCA check)

Columns:
| Column | Description |
|--------|------------|
| `Status` | `WAIVED`, `WAIVED_EXPIRING_SOON`, `VIOLATION`, `EXPIRED_WAIVER` |
| `Rule` | Name of scanner rule (e.g., `ApexDoc`, `no-unused-vars`) |
| `File` | Source file with violation (e.g., `force-app/main/default/classes/MyClass.cls`) |
| `Line` | Line number of violation |
| `Severity` | High (3) or Critical (4) |
| `Description` | Human-readable violation message |
| `Expiry` | Waiver expiration date (if applicable) |
| `Days_Left` | Days until expiry (if applicable) |
| `Reason` | Waiver justification (if waived) |
| `Approved_By` | Approver username (if waived) |
| `Approved_Date` | Approval date (if waived) |

---

## Part 2: npm Dependency (SCA) Waivers

### Overview

File: `.github/sca-waivers.json`

Waivers for npm `npm audit` high/critical vulnerabilities discovered during `sca-sast-stage` job.

---

### JSON Schema

```json
{
  "package": "lodash",
  "severity": "high",
  "advisory": "GHSA-xxxx-xxxx-xxxx",
  "reason": "No fix available. Legacy dependency.",
  "expires": "2026-06-30",
  "approved_by": "platform-security"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `package` | ✅ | NPM package name (e.g., `lodash`, `express`) |
| `severity` | ✅ | `high` or `critical` |
| `advisory` | ✅ | GHSA identifier (e.g., `GHSA-35jh-r3h4-6jhm`) — aids tracking |
| `reason` | ✅ | Why waiver is needed (e.g., "Transitive only", "Awaiting upstream fix") |
| `expires` | ✅ | Expiration date in ISO format: `YYYY-MM-DD` |
| `approved_by` | ✅ | Team or username authorizing the waiver |

---

### Example Waivers

```json
[
  {
    "package": "lodash",
    "severity": "high",
    "advisory": "GHSA-35jh-r3h4-6jhm",
    "reason": "Transitive dependency. Not directly used — upgrade of parent in progress.",
    "expires": "2026-06-30",
    "approved_by": "platform-security"
  },
  {
    "package": "minimist",
    "severity": "critical",
    "advisory": "GHSA-xvch-5gqq-393w",
    "reason": "Dev-only dependency. Fixed in minimist@1.2.8 — upgrade in PR #456.",
    "expires": "2026-05-15",
    "approved_by": "devops-team"
  },
  {
    "package": "express",
    "severity": "high",
    "advisory": "GHSA-9f97-04qc-545m",
    "reason": "Vulnerability in express@4.17.x. Framework upgrade to v5 in progress (Q3).",
    "expires": "2026-07-31",
    "approved_by": "architecture"
  }
]
```

---

### Waiver Workflow

1. **Developer** runs `npm audit` locally, finds high/critical vulnerabilities
2. **Developer** evaluates fix feasibility:
   - If fixable: upgrade package, commit, close issue
   - If not fixable: create GitHub issue + add waiver to `.github/sca-waivers.json`
3. **Tech Lead** reviews waiver in PR:
   - Validates reason
   - Approves if acceptable
4. **Merge** to main
5. **Pipeline** checks waivers on future PRs

---

### Expired Waiver Handling

When a waiver expires:
- Pipeline logs: `❌ EXPIRED WAIVER [critical] lodash`
- **Fails** `sca-sast-stage` job
- Developer must either:
  - **Fix** the vulnerability (upgrade package), OR
  - **Renew** the waiver with new expiry date + updated reason

---

## Monitoring & Reporting

### Per-PR Report
Pipeline posts SCA governance report as PR comment showing:
- Total violations: _count_
- Waived violations: _count_
- Expired waivers: _count_
- Unwaived violations: _count_

Example:
```
## SCA Governance Report

✅ Waived (active): 3
❌ Expired waivers: 1
⚠️ Violations (no waiver): 2
```

### Artifacts
After each PR validation, artifacts uploaded for 30 days:
- `sfdx-report.csv` — Raw scanner output
- `sca-governance-report.csv` — Waiver-annotated results
- `fetched-waivers.csv` — Waivers used for check

---

## Best Practices

1. **Minimize waiver scope** — prefer specific file/rule combo over global
2. **Set realistic expiries** — 30–90 days typical
3. **Track in Jira** — always reference ticket in reason
4. **Rotate approval** — use different approvers per month (audit trail)
5. **Review monthly** — check for expiring waivers (⏰ status)
6. **Retire global waivers** — if not used for 3 months, remove and revoke

---

## Links

- [Pipeline Setup Guide](pipeline-setup.md)
- [Manual Runbook](manual_runbook.md)
- [Troubleshooting](troubleshooting.md)
