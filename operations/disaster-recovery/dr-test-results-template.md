# DR Test Results — Cross-Cloud (ARO ↔ ROSA HCP)

Record outcomes from [DR Drill Checklist](./dr-drill-checklist.md) exercises.

---

## Test Summary

| Field | Value |
|-------|-------|
| Test ID | DR-YYYY-MM-DD-001 |
| Date | |
| Environment | ☐ Non-Prod ☐ Production (controlled drill) |
| Primary | ☐ ARO · ☐ ROSA HCP |
| DR | ☐ ROSA HCP · ☐ ARO |
| Tier | ☐ Cold · ☐ Pilot · ☐ Passive · ☐ Active/Active |
| Test type | ☐ Backup restore · ☐ Failover · ☐ Failback · ☐ Tabletop |

---

## Targets vs Actuals

| Metric | Approved Target | Measured Actual | Pass ☐ |
|--------|-----------------|-----------------|--------|
| RTO | | | |
| RPO | | | |
| OADP restore time | | | |
| DNS propagation | | | |
| DB promotion lag at cutover | | | |

---

## Timeline (UTC)

| Time | Event |
|------|-------|
| | Drill started |
| | Disaster declared (simulated) |
| | Data promotion / restore complete |
| | Traffic cutover complete |
| | Smoke tests passed |
| | Failback started (if applicable) |
| | Primary restored |
| | Drill closed |

---

## Issues Found

| # | Issue | Severity | Owner | Remediation | Due Date |
|---|-------|----------|-------|-------------|----------|
| 1 | | | | | |
| 2 | | | | | |

---

## Runbook Updates

| Runbook | Change Required | PR / Ticket |
|---------|-----------------|-------------|
| failover-runbook-aro-rosa.md | | |
| failback-runbook-aro-rosa.md | | |
| oadp_cross_cloud_s3_guide.md | | |

---

## Sign-Off

| Role | Name | Date |
|------|------|------|
| SRE | | |
| Architect | | |
| Business Owner | | |

**Next drill scheduled:** ____________
