# Source document reconciliation

**Status:** Primary catalog is the two PDFs under [`docs/`](../../). Google Docs remain optional secondary references.

## Authoritative sources

| Document | Location | Role |
|----------|----------|------|
| ROSA Technical Solutions | [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) | UC-01 … UC-07 (Scenarios 1–7) |
| ROSA Ingress Architectures | [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf) | ING-01 … ING-06 |

## PDF scenario → runbook mapping

| PDF reference | Runbook ID | File |
|---------------|------------|------|
| Technical Solutions — Scenario 1 | UC-01 | [02-alb-acm-instance-mode.md](02-alb-acm-instance-mode.md) |
| Technical Solutions — Scenario 2 | UC-02 | [03-irsa-s3-workload.md](03-irsa-s3-workload.md) |
| Technical Solutions — Scenario 3 | UC-03 | [04-ebs-gp3-pvc.md](04-ebs-gp3-pvc.md) |
| Technical Solutions — Scenario 4 | UC-04 | [05-user-workload-monitoring.md](05-user-workload-monitoring.md) |
| Technical Solutions — Scenario 5 | UC-05 | [06-gpu-machinepool-baremetal.md](06-gpu-machinepool-baremetal.md) |
| Technical Solutions — Scenario 6 | UC-06 | [07-terraform-project-helm.md](07-terraform-project-helm.md) |
| Technical Solutions — Scenario 7 | UC-07 | [08-virt-rhel-cloudinit.md](08-virt-rhel-cloudinit.md) |
| Ingress Architectures — §1 | ING-01 | [09-routes-haproxy-ingress.md](09-routes-haproxy-ingress.md) |
| Ingress Architectures — §2 | ING-02 | [10-edge-alb-fronted-ingress.md](10-edge-alb-fronted-ingress.md) |
| Ingress Architectures — §3 | ING-03 → UC-01 | [02-alb-acm-instance-mode.md](02-alb-acm-instance-mode.md) |
| Ingress Architectures — §4 | ING-04 | [11-metallb-bgp-ingress.md](11-metallb-bgp-ingress.md) |
| Ingress Architectures — §5 | ING-05 | [12-virt-ipsec-vpn-ingress.md](12-virt-ipsec-vpn-ingress.md) |
| Ingress Architectures — §6 | ING-06 | [13-openshift-service-mesh.md](13-openshift-service-mesh.md) |

## Known PDF vs platform reconciliation

| Topic | Technical Solutions PDF | Ingress PDF + ROSA platform |
|-------|-------------------------|-----------------------------|
| ALB `target-type: ip` + readiness gates | Described as supported path | **Not supported** on OVN; use **instance** mode only |
| Validation | Compare instance vs IP | PASS on instance; IP = negative / N/A test in UC-01 |

## Optional secondary sources

| Document | URL | Notes |
|----------|-----|--------|
| Google Doc A | [1ds3_F0GNj4…](https://docs.google.com/document/d/1ds3_F0GNj4CovKghu67JH8WO5cwfcLamXSL6LXHoWLM/edit) | Not used for this folder revision; reconcile manually if QE IDs differ |
| Google Doc B | [193yRGltNtK2…](https://docs.google.com/document/d/193yRGltNtK2PeeXug9nlpGYoMj3ICSczJpEj_LC6Mo4/edit) | Same |

## Maintenance

When PDFs are updated:

1. Diff scenario text against the matching runbook file.
2. Update pass/fail matrix titles in [README.md](README.md) if names change.
3. Record execution in [validation-report.md](validation-report.md).
