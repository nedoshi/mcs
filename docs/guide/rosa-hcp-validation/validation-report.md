# ROSA use-case validation — execution report

Template for recording live QE runs against [README.md](README.md) pass/fail matrix.

## Run metadata

| Field | Value |
|-------|--------|
| Cluster name | |
| ROSA type | HCP / Classic |
| OpenShift version | |
| Region | |
| Cluster profile | Standard / Bare metal |
| Tester | |
| Date range | |

## Results

| ID | Test | Result | Date | Notes |
|----|------|--------|------|-------|
| — | Prerequisites | PENDING | | |
| UC-01 | ALB + ACM (instance mode) | PENDING | | Include UC-01N IP negative if run |
| UC-02 | IRSA → S3 | PENDING | | |
| UC-03 | EBS gp3 PVC | PENDING | | |
| UC-04 | User Workload Monitoring | PENDING | | |
| UC-05 | GPU machine pool | PENDING | | BLOCKED if no metal |
| UC-06 | Terraform + Helm | PENDING | | |
| UC-07 | Virt RHEL cloud-init | PENDING | | BLOCKED if no metal |
| ING-01 | Routes / HAProxy | PENDING | | |
| ING-02 | Edge ALB + Ingress | PENDING | | |
| ING-04 | MetalLB BGP | PENDING | | |
| ING-05 | Virt IPsec VPN | PENDING | | |
| ING-06 | Service Mesh | PENDING | | |

**Result values:** `PASS` | `FAIL` | `BLOCKED` | `PENDING`

## Blockers log

| ID | Blocker | Resolution |
|----|---------|------------|
| | | |

## Sign-off

- [ ] All applicable rows marked PASS or BLOCKED with justification
- [ ] [gap-analysis.md](gap-analysis.md) updated if new repo gaps found
- [ ] PDF reconciliation reviewed ([source-doc-reconciliation.md](source-doc-reconciliation.md))
