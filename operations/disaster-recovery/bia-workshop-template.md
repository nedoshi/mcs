# Cross-Cloud DR Business Impact Analysis (BIA) Workshop Template

Use this template in a workshop with business stakeholders **before** choosing DR tiers or primary/DR cloud direction. Complete one row per application or service.

**Related:** [Cross-Cloud DR Guide](../../docs/guide/cross-cloud-dr-aro-rosa/README.md) · [Stateful Workload Inventory](./stateful-workload-inventory.md)

---

## Workshop Metadata

| Field | Value |
|-------|-------|
| Date | |
| Facilitator | |
| Attendees (Business) | |
| Attendees (Engineering) | |
| Primary cloud direction | ☐ ARO primary → ROSA DR · ☐ ROSA primary → ARO DR · ☐ Active/Active |
| Target OpenShift version (both clouds) | |

---

## Criticality Tier Definitions

| Tier | Example Workloads | Target RTO | Target RPO | Typical DR Strategy |
|------|-------------------|------------|------------|---------------------|
| **Tier 0 — Mission Critical** | Checkout, payments, patient safety | Seconds–minutes | Near-zero | Active/Active |
| **Tier 1 — Business Critical** | Core customer-facing apps | Minutes–1 hr | Minutes | Active/Passive |
| **Tier 2 — Business Operational** | Internal LOB, reporting | Hours | Hours | Pilot Light |
| **Tier 3 — Standard / Non-Critical** | Dev tooling, batch jobs | Same day | 24 hrs | Backup & Restore |

---

## Application Classification Worksheet

| App / Service | Owner | Tier (0–3) | Approved RTO | Approved RPO | DR Strategy | Primary Cloud | DR Cloud | Business Sign-off |
|---------------|-------|------------|--------------|--------------|-------------|---------------|----------|-------------------|
| | | | | | | ARO / ROSA | ROSA / ARO | ☐ |
| | | | | | | | | ☐ |
| | | | | | | | | ☐ |

---

## Platform Direction Decision

Answer these before provisioning DR infrastructure:

| # | Question | Decision | Notes |
|---|----------|----------|-------|
| 1 | Which cloud hosts primary production traffic? | | |
| 2 | Which cloud is DR standby? | | |
| 3 | Is Active/Active required for any Tier 0 app? | ☐ Yes ☐ No | |
| 4 | Can data legally replicate to the DR cloud/region? | ☐ Yes ☐ No | GDPR, HIPAA, sovereign cloud |
| 5 | Standing DR cost model approved (Cold / Pilot / Passive)? | ☐ Yes ☐ No | FinOps sign-off |
| 6 | Cross-cloud egress budget approved? | ☐ Yes ☐ No | DB replication, backup sync |

---

## DR Tier Assignment Summary

After classification, summarize platform-wide posture (tiers may differ per app):

| DR Tier | App Count | Standing Cost Profile | Implementation Reference |
|---------|-----------|----------------------|--------------------------|
| Backup & Restore (Cold) | | Backup storage only | [Failover Runbook](./failover-runbook-aro-rosa.md) §Cold |
| Pilot Light | | Minimal DR cluster 24/7 | [Failover Runbook](./failover-runbook-aro-rosa.md) §Pilot |
| Active/Passive | | Full duplicate compute idle | [Data Replication Guide](./data-replication-guide.md) |
| Active/Active | | Both regions serve traffic | [Traffic Steering Guide](./traffic-steering-guide.md) |

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Business Owner | | | |
| Cloud Architect | | | |
| FinOps | | | |
| GRC / Compliance | | | |
