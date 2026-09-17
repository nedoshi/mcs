---
date: '2026-09-17'
title: 'ROSA use-case validation (HCP-ready cluster)'
tags: ["ROSA", "ROSA HCP", "Validation", "QE", "Ingress", "Workloads"]
authors:
  - Red Hat Cloud Experts
related_guides:
  - source-doc-reconciliation.md
  - 01-prerequisites.md
  - gap-analysis.md
  - validation-report.md
---

# ROSA use-case validation (HCP-ready cluster)

QE runbooks for **application and ingress use cases** on Red Hat OpenShift Service on AWS (ROSA), typically on a **ready ROSA HCP** cluster. Scenarios are derived from authoritative PDFs in [`docs/`](../../), not from cluster install/lifecycle checklists.

**Platform install** (if you need a cluster first): [hcp-ansible](../../../cluster-creation-cloud/aws/hcp-ansible/) · [tf-rosa](../../../cluster-creation-cloud/aws/tf-rosa/) · [use-cases map](../../../cluster-creation-cloud/aws/docs/use-cases.md)

## Authoritative sources

| Document | Path |
|----------|------|
| Technical Solutions (Scenarios 1–7) | [ROSA Technical Solutions.pdf](../../ROSA%20Technical%20Solutions.pdf) |
| Ingress patterns (6 architectures) | [ROSA Ingress Architectures.pdf](../../ROSA%20Ingress%20Architectures.pdf) |

> **ALB IP mode:** [Technical Solutions](../../ROSA%20Technical%20Solutions.pdf) Scenario 1 describes `target-type: ip` and Pod Readiness Gates. On ROSA (OVN-Kubernetes), **IP target mode is not supported**—validate **instance** mode only; see [02-alb-acm-instance-mode.md](02-alb-acm-instance-mode.md). ING-03 is covered by UC-01.

## Quick start

```bash
export ROSA_TOKEN="<from console.redhat.com/openshift/token/rosa>"
export AWS_DEFAULT_REGION="<region>"
export CLUSTER_NAME="<cluster>"
export KUBECONFIG="${HOME}/.kube/${CLUSTER_NAME}"

rosa login --token="${ROSA_TOKEN}"
rosa describe cluster -c "${CLUSTER_NAME}" | grep -E 'State|API URL'
# State: ready
rosa create admin --cluster "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}"  # if needed
```

Complete [01-prerequisites.md](01-prerequisites.md) before UC/ING tests.

## Runbook index

| ID | Document | PDF source |
|----|----------|------------|
| — | [01-prerequisites.md](01-prerequisites.md) | Both |
| UC-01 | [02-alb-acm-instance-mode.md](02-alb-acm-instance-mode.md) | TS Scenario 1 · Ingress §3 (ING-03) |
| UC-02 | [03-irsa-s3-workload.md](03-irsa-s3-workload.md) | TS Scenario 2 |
| UC-03 | [04-ebs-gp3-pvc.md](04-ebs-gp3-pvc.md) | TS Scenario 3 |
| UC-04 | [05-user-workload-monitoring.md](05-user-workload-monitoring.md) | TS Scenario 4 |
| UC-05 | [06-gpu-machinepool-baremetal.md](06-gpu-machinepool-baremetal.md) | TS Scenario 5 |
| UC-06 | [07-terraform-project-helm.md](07-terraform-project-helm.md) | TS Scenario 6 |
| UC-07 | [08-virt-rhel-cloudinit.md](08-virt-rhel-cloudinit.md) | TS Scenario 7 |
| ING-01 | [09-routes-haproxy-ingress.md](09-routes-haproxy-ingress.md) | Ingress §1 |
| ING-02 | [10-edge-alb-fronted-ingress.md](10-edge-alb-fronted-ingress.md) | Ingress §2 |
| ING-04 | [11-metallb-bgp-ingress.md](11-metallb-bgp-ingress.md) | Ingress §4 |
| ING-05 | [12-virt-ipsec-vpn-ingress.md](12-virt-ipsec-vpn-ingress.md) | Ingress §5 |
| ING-06 | [13-openshift-service-mesh.md](13-openshift-service-mesh.md) | Ingress §6 |
| — | [gap-analysis.md](gap-analysis.md) | MCS repo coverage |
| — | [validation-report.md](validation-report.md) | Execution log |

## Recommended execution order

1. Prerequisites + cluster `ready`
2. ING-01 → UC-02, UC-03, UC-04
3. UC-01 and/or ING-02
4. UC-06
5. UC-05, UC-07, ING-05 (bare metal / virt track)
6. ING-04, ING-06 (optional advanced)

## Pass/fail matrix

Record during live runs. Details in [validation-report.md](validation-report.md).

| ID | Test | Procedure | Result | Date | Notes |
|----|------|-----------|--------|------|-------|
| — | Prerequisites | [01-prerequisites.md](01-prerequisites.md) | | | |
| UC-01 | ALB + ACM (instance mode) | [02-alb-acm-instance-mode.md](02-alb-acm-instance-mode.md) | | | ING-03 merged |
| UC-02 | IRSA → S3 | [03-irsa-s3-workload.md](03-irsa-s3-workload.md) | | | |
| UC-03 | EBS gp3 PVC | [04-ebs-gp3-pvc.md](04-ebs-gp3-pvc.md) | | | |
| UC-04 | User Workload Monitoring | [05-user-workload-monitoring.md](05-user-workload-monitoring.md) | | | |
| UC-05 | GPU machine pool (metal) | [06-gpu-machinepool-baremetal.md](06-gpu-machinepool-baremetal.md) | | | |
| UC-06 | Terraform Project + Helm | [07-terraform-project-helm.md](07-terraform-project-helm.md) | | | |
| UC-07 | Virt RHEL + cloud-init | [08-virt-rhel-cloudinit.md](08-virt-rhel-cloudinit.md) | | | |
| ING-01 | Routes / HAProxy | [09-routes-haproxy-ingress.md](09-routes-haproxy-ingress.md) | | | |
| ING-02 | Edge ALB + Ingress | [10-edge-alb-fronted-ingress.md](10-edge-alb-fronted-ingress.md) | | | |
| ING-04 | MetalLB BGP | [11-metallb-bgp-ingress.md](11-metallb-bgp-ingress.md) | | | |
| ING-05 | Virt IPsec VPN ingress | [12-virt-ipsec-vpn-ingress.md](12-virt-ipsec-vpn-ingress.md) | | | |
| ING-06 | Service Mesh (Istio) | [13-openshift-service-mesh.md](13-openshift-service-mesh.md) | | | |

**Result values:** `PASS` | `FAIL` | `BLOCKED` | `PENDING`

## Related repository documentation

| Topic | Path |
|-------|------|
| ALB IngressGroup demo | [networking/load-balancers/alb-ingress-grouping/](../../../networking/load-balancers/alb-ingress-grouping/) |
| UWM + AMP federation | [federating_metrics_to_aws_prometheus.md](../../troubleshooting/ROSA/federating_metrics_to_aws_prometheus.md) |
| Service Mesh + Entra | [rosa_service_mesh_entraid.md](../../troubleshooting/ROSA/rosa_service_mesh_entraid.md) |
| ROSA network / Virt | [ROSA_Network_Troubleshooting_Guide.md](../../network-troubleshooting/ROSA/ROSA_Network_Troubleshooting_Guide.md) |
| Shared VPC (install) | [ROSA-HCP-SharedVPC-Installation-Tutorial.md](../../../cluster-creation-cloud/aws/docs/hcp-shared-vpc/ROSA-HCP-SharedVPC-Installation-Tutorial.md) |
| ARO HCP validation (parallel) | [aro-hcp-validation](../aro-hcp-validation/README.md) |
