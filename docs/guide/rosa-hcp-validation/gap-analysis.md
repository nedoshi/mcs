# ROSA use-case validation — gap analysis

Living document: MCS repository automation vs PDF-derived test cases.

## Coverage vs use cases

| ID | Topic | Repo assets | Gap |
|----|-------|-------------|-----|
| UC-01 | ALB + ACM (instance) | [alb-ingress-grouping](../../../networking/load-balancers/alb-ingress-grouping/) (`install-albo.sh`, manifests) | ACM cert ARN manual; HTTPS path not in demo (HTTP only) |
| UC-02 | IRSA | `tf-rosa` STS/OIDC patterns; no dedicated S3 smoke script | IAM trust + bucket setup manual per lab |
| UC-03 | EBS gp3 | Default `gp3-csi` / EBS CSI operator on ROSA | Custom IOPS/throughput SC rarely scripted |
| UC-04 | UWM | [federating_metrics_to_aws_prometheus.md](../../troubleshooting/ROSA/federating_metrics_to_aws_prometheus.md) | PodMonitor/PrometheusRule not in CI |
| UC-05 | GPU on metal | [rosa-zero-hcp.md](../../../cluster-creation-cloud/aws/docs/reference/rosa-zero-hcp.md) GPU notes | Bare metal pool + GPU Operator not automated in this repo |
| UC-06 | Terraform + Helm | [tf-rosa](../../../cluster-creation-cloud/aws/tf-rosa/) cluster provision only | No sample `kubernetes_manifest` Project + Helm in tree |
| UC-07 | Virt RHEL cloud-init | Network troubleshooting Virt section | Full Terraform VM manifest not checked in |
| ING-01 | Routes | Standard ROSA default router | cert-manager / External DNS optional—manual |
| ING-02 | Edge ALB + Ingress | Troubleshooting public ALB chain refs | No single scripted end-to-end lab |
| ING-04 | MetalLB BGP | [openshift-port-strategy.md](../../architecture/networking/openshift-port-strategy.md) mentions MetalLB | No ROSA BGP peering lab in MCS |
| ING-05 | IPsec VPN for Virt | PDF / MOBB external links | High infra bar (TGW, CUDN)—manual only |
| ING-06 | Service Mesh | [rosa_service_mesh_entraid.md](../../troubleshooting/ROSA/rosa_service_mesh_entraid.md) | Entra-focused; generic mesh smoke separate |

## Cluster profile gaps

| Profile | Use cases | Repo install path |
|---------|-----------|-------------------|
| Standard HCP workers (EC2 VM) | UC-01–04, UC-06, ING-01–02, ING-06 | `hcp-ansible`, `tf-rosa` |
| Bare metal workers | UC-05, UC-07, ING-05 | Not default in `hcp-ansible`; custom machine pools |

## Recommended automation (phase 2)

- `scripts/validate-cluster.sh` mirroring [aro-hcp-validation](../aro-hcp-validation/scripts/) for ING-01 + UC-03 smoke only.
- Extend `alb-ingress-grouping` with ACM HTTPS sample Ingress matching UC-01.

## Execution priority for QE labs

1. Standard profile: Prerequisites → ING-01 → UC-02–04 → UC-01
2. IaC: UC-06
3. Metal profile (if available): UC-07 → UC-05 → ING-05
4. Optional: ING-02, ING-04, ING-06
