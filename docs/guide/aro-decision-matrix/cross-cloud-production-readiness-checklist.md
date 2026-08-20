---
date: '2026-08-20'
title: 'Cross-Cloud DR Production Readiness Checklist — ARO ↔ ROSA HCP'
tags: ["ARO", "ROSA", "Checklist", "Disaster Recovery", "Multi-Cloud"]
---

# Cross-Cloud DR Production Readiness Checklist

Extends [ARO Production Readiness Checklist](./production-readiness-checklist.md) items **5.6–5.7** and GitOps gates for **ARO ↔ ROSA HCP** disaster recovery pairs.

Use alongside [Cross-Cloud DR Guide](../cross-cloud-dr-aro-rosa/README.md).

**DR pair ID:** ____________________  
**Primary cloud:** ☐ ARO (Azure) · ☐ ROSA HCP (AWS)  
**DR cloud:** ☐ ROSA HCP (AWS) · ☐ ARO (Azure)  
**OpenShift version (both):** ____________________

---

## Phase 0: BIA & Direction

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| X0.1 | BIA workshop completed — [template](../../operations/disaster-recovery/bia-workshop-template.md) | Business | | ☐ |
| X0.2 | Stateful workload inventory complete | Architect | | ☐ |
| X0.3 | Primary / DR cloud direction documented | Architect | | ☐ |
| X0.4 | Data residency approved for cross-cloud replication | GRC | | ☐ |
| X0.5 | Cross-cloud egress cost approved | FinOps | | ☐ |

---

## Phase 1: Infrastructure (Both Clusters)

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| X1.1 | DR tfvars committed — [environments/](../../cluster-creation-cloud/cross-cloud-dr/environments/) | Platform | | ☐ |
| X1.2 | Same OpenShift minor version on primary and DR | Platform | | ☐ |
| X1.3 | Non-overlapping CIDRs verified | Network | | ☐ |
| X1.4 | Quota reserved in DR cloud for failover scale | Platform | | ☐ |
| X1.5 | Cross-cloud VPN provisioned (if DB replication required) | Network | | ☐ |

---

## Phase 2: GitOps & ACM

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| X2.1 | Both clusters registered in ACM with `dr-pair` labels | DevOps | | ☐ |
| X2.2 | ApplicationSets syncing to DR cluster continuously | DevOps | | ☐ |
| X2.3 | Cluster values committed for primary and DR | DevOps | | ☐ |
| X2.4 | ACM hub survivability documented | Architect | | ☐ |

Reference: [ACM GitOps Setup](../../operations/disaster-recovery/acm-gitops-setup.md)

---

## Phase 3: Identity & Registry

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| X3.1 | Entra ID redirect URIs for both cluster domains | Security | | ☐ |
| X3.2 | Same Entra groups mapped to RBAC on both clusters | Security | | ☐ |
| X3.3 | Break-glass creds in neutral vault | Security | | ☐ |
| X3.4 | Cloud-neutral or dual-push registry implemented | DevOps | | ☐ |
| X3.5 | DR cluster image pull tested with primary registry offline | DevOps | | ☐ |

Reference: [Identity & Registry Setup](../../operations/disaster-recovery/identity-registry-setup.md)

---

## Phase 4: Backup & Data (extends 5.6–5.7)

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| X4.1 | OADP installed on primary and DR clusters | SRE | | ☐ |
| X4.2 | S3 backup target with versioning / Object Lock | SRE | | ☐ |
| X4.3 | Kopia/datamover enabled (no cross-cloud CSI snapshot dependency) | SRE | | ☐ |
| X4.4 | **5.6** Backup solution deployed (OADP cross-cloud) | SRE | | ☐ |
| X4.5 | **5.7** Cross-cloud restore test completed — time recorded | SRE | | ☐ |
| X4.6 | Tier 1 DB replication configured and lag monitored | App Team | | ☐ |
| X4.7 | Secrets replicated to both cloud vaults (ESO) | Security | | ☐ |

Reference: [OADP Cross-Cloud S3 Guide](../../operations/backup-restore/oadp_cross_cloud_s3_guide.md)

---

## Phase 5: Traffic & Runbooks

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| X5.1 | Global DNS / LB with health checks configured | Network | | ☐ |
| X5.2 | DNS TTL supports target RTO | Network | | ☐ |
| X5.3 | Failover runbook published and accessible offline | SRE | | ☐ |
| X5.4 | Failback runbook published | SRE | | ☐ |
| X5.5 | Disaster declaration authority documented | Management | | ☐ |

Reference: [Traffic Steering Guide](../../operations/disaster-recovery/traffic-steering-guide.md)

---

## Phase 6: Validation

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| X6.1 | Quarterly failover drill completed | SRE | | ☐ |
| X6.2 | Annual failback drill completed | SRE | | ☐ |
| X6.3 | RTO / RPO measured vs targets — [results template](../../operations/disaster-recovery/dr-test-results-template.md) | SRE | | ☐ |
| X6.4 | Tabletop exercise completed (2×/year) | SRE | | ☐ |

Reference: [DR Drill Checklist](../../operations/disaster-recovery/dr-drill-checklist.md)

---

## Sign-Off

| Role | Name | Date |
|------|------|------|
| Cloud Architect | | |
| SRE Lead | | |
| Security / GRC | | |
| Business Owner | | |
