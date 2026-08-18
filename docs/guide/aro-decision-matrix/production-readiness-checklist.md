---
date: '2026-08-18'
title: 'ARO Production Readiness Checklist'
tags: ["ARO", "Checklist"]
---

# ARO Production Readiness Checklist

Use this checklist alongside the [ARO Decision Matrix](./README.md). Record answers, owners, and sign-off dates.

**Cluster name:** ____________________  
**Region:** ____________________  
**OpenShift version:** ____________________  
**Environment:** ☐ Production  ☐ Regulated  ☐ Pre-Production  

---

## Phase 0: Planning Sign-Off

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| 0.1 | Decision matrix reviewed (all 20 questions) | Architect | | ☐ |
| 0.2 | Data residency / compliance requirements documented | GRC | | ☐ |
| 0.3 | RPO / RTO targets defined | Business | | ☐ |
| 0.4 | Cost estimate approved (compute + network + storage) | FinOps | | ☐ |

---

## Phase 1: Region, Zone & Capacity (Pre-Install)

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| 1.1 | Target region is ARO-supported (`az provider show`) | Platform | | ☐ |
| 1.2 | OpenShift version available in region (`az aro get-versions`) | Platform | | ☐ |
| 1.3 | Availability Zone support evaluated for region | Architect | | ☐ |
| 1.4 | Master SKU available in region (`az vm list-skus`) | Platform | | ☐ |
| 1.5 | Worker SKU available in region (`az vm list-skus`) | Platform | | ☐ |
| 1.6 | vCPU quota ≥ 40 cores (60+ recommended) | Platform | | ☐ |
| 1.7 | vCPU headroom ≥ 2× control plane vCPU | Platform | | ☐ |
| 1.8 | Fallback SKU documented if primary unavailable | Architect | | ☐ |
| 1.9 | Region/SKU validation runbook output attached | Platform | | ☐ |

**Recorded SKUs**

| Role | VM Size | Count | vCPU | Memory |
|------|---------|-------|------|--------|
| Control plane | | 3 | | |
| Worker | | | | |
| Infrastructure (if any) | | 3 | | |

---

## Phase 2: Identity & Access

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| 2.1 | Managed Identity selected (not Service Principal) | Security | | ☐ |
| 2.2 | 9 user-assigned identities created | Platform | | ☐ |
| 2.3 | ARO built-in roles assigned to identities | Platform | | ☐ |
| 2.4 | Deployer has Contributor + User Access Administrator on RG | Platform | | ☐ |
| 2.5 | Azure AD / Entra ID integration configured | Security | | ☐ |
| 2.6 | Cluster RBAC groups mapped (cluster-admin minimized) | Security | | ☐ |
| 2.7 | kubeadmin disabled after IdP validation | Security | | ☐ |

---

## Phase 3: Network

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| 3.1 | Private cluster visibility selected | Architect | | ☐ |
| 3.2 | VNet CIDR planned (no overlap) | Network | | ☐ |
| 3.3 | Master subnet ≥ /27 (recommended /26) | Network | | ☐ |
| 3.4 | Worker subnet ≥ /27 (recommended /24) | Network | | ☐ |
| 3.5 | Hub-spoke or single VNet design approved | Network | | ☐ |
| 3.6 | Admin access path tested (VPN / ER / Bastion) | Network | | ☐ |
| 3.7 | Egress model defined (UDR / Egress Lockdown) | Network | | ☐ |
| 3.8 | Required firewall allowlist documented | Security | | ☐ |
| 3.9 | NSG model selected (ARO-managed vs BYO) | Network | | ☐ |
| 3.10 | Custom domain DNS plan (if applicable) | Network | | ☐ |

---

## Phase 4: Cluster Install Validation

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| 4.1 | `Microsoft.RedHatOpenShift` provider registered | Platform | | ☐ |
| 4.2 | Red Hat pull secret applied | Platform | | ☐ |
| 4.3 | Cluster deployed successfully | Platform | | ☐ |
| 4.4 | All ClusterOperators Available (`oc get co`) | Platform | | ☐ |
| 4.5 | All nodes Ready (`oc get nodes`) | Platform | | ☐ |
| 4.6 | Nodes distributed across AZs (if region supports AZ) | Platform | | ☐ |
| 4.7 | Console and API accessible via approved path | Platform | | ☐ |

---

## Phase 5: Day-2 Operations (Production Gate)

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| 5.1 | User workload monitoring enabled | SRE | | ☐ |
| 5.2 | Cluster logging / forwarder deployed | SRE | | ☐ |
| 5.3 | Logs forwarded to SIEM / Azure Monitor | SRE | | ☐ |
| 5.4 | API audit logging configured | Security | | ☐ |
| 5.5 | Alerting integrated with on-call | SRE | | ☐ |
| 5.6 | Backup solution deployed (OADP) | SRE | | ☐ |
| 5.7 | Backup restore test completed | SRE | | ☐ |
| 5.8 | Pod Disruption Budgets for critical workloads | App Team | | ☐ |
| 5.9 | Network policies applied (multi-tenant) | Security | | ☐ |
| 5.10 | Resource tagging applied per policy | Platform | | ☐ |

---

## Phase 6: GitOps & CD

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| 6.1 | OpenShift GitOps operator installed | DevOps | | ☐ |
| 6.2 | Argo CD Applications defined for workloads | DevOps | | ☐ |
| 6.3 | Git repo branch strategy documented | DevOps | | ☐ |
| 6.4 | Promotion path Dev → Staging → Prod tested | DevOps | | ☐ |
| 6.5 | Rollback via Git revert tested | DevOps | | ☐ |
| 6.6 | Octopus Deploy integrated (if applicable) | DevOps | | ☐ |
| 6.7 | Octopus gateway outbound connectivity verified | DevOps | | ☐ |

---

## Phase 7: Security & Compliance

| # | Item | Owner | Date | Status |
|---|------|-------|------|--------|
| 7.1 | Support policy constraints reviewed | Security | | ☐ |
| 7.2 | CMK / BYOK configured (if required) | Security | | ☐ |
| 7.3 | Image scanning integrated | Security | | ☐ |
| 7.4 | Secrets stored in Key Vault / sealed secrets | Security | | ☐ |
| 7.5 | Azure Policy assignments validated | GRC | | ☐ |
| 7.6 | Penetration test / security review completed | Security | | ☐ |

---

## Phase 8: Go-Live Sign-Off

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Cloud Architect | | | |
| Platform Engineering Lead | | | |
| Security / GRC | | | |
| Application Owner | | | |
| Operations / SRE | | | |

**Production go-live approved:** ☐ Yes  ☐ No  

**Notes:**

_______________________________________________________________________________

_______________________________________________________________________________

_______________________________________________________________________________

---

## Quick Validation Commands

```bash
# Cluster health
oc get co
oc get nodes -o wide

# Zone distribution (look for topology.kubernetes.io/zone label)
oc get nodes -L topology.kubernetes.io/zone

# Version
oc get clusterversion

# ARO cluster details
az aro show -n <cluster> -g <rg> -o table
```
