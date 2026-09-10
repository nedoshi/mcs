---
date: '2026-08-20'
title: 'ARO HCP Validation — Master Checklist'
tags: ["ARO", "ARO HCP", "Validation", "External Authentication", "MOBB"]
authors:
  - Red Hat Cloud Experts
validated_version: "preview (2024-06-10-preview API)"
related_guides:
  - 01-prerequisites.md
  - gap-analysis.md
  - validation-report.md
---

# ARO HCP Validation — Master Checklist

> **Preview notice:** ARO HCP and external authentication integration are pre-GA. Pin API versions in scripts and re-validate when Microsoft publishes GA documentation.

This folder is the **Phase 1 validation runbook** for Azure Red Hat OpenShift Hosted Control Planes (ARO HCP). Workshop content ([bookbag-aro-mobb](https://github.com/rh-mobb/bookbag-aro-mobb)) is deferred until this checklist passes.

## Quick start

```bash
cd docs/guide/aro-hcp-validation/scripts
cp env.example env.sh
# Edit env.sh with your subscription, cluster, and RHBK values
source env.sh

# After cluster is provisioned (see 02-provision-azure-cli.md):
chmod +x request-aro-admin-credential.sh validate-cluster.sh
./request-aro-admin-credential.sh
export KUBECONFIG="$(pwd)/aro-cluster.kubeconfig"
./validate-cluster.sh
```

## Runbook index

| Step | Document | Scripts |
|------|----------|---------|
| Prerequisites | [01-prerequisites.md](01-prerequisites.md) | — |
| Path A — Provision | [02-provision-azure-cli.md](02-provision-azure-cli.md) | — |
| External auth (RHBK) | [03-external-auth-rhbk.md](03-external-auth-rhbk.md) | `externalauth.bicep` |
| Admin credential | [04-admin-credential.md](04-admin-credential.md) | `request-aro-admin-credential.sh` |
| Day-2 smoke tests | [05-smoke-tests.md](05-smoke-tests.md) | `validate-cluster.sh` |
| Path B — Terraform | [06-terraform-aro-hcp.md](06-terraform-aro-hcp.md) | `cluster-creation-cloud/azure/terraform-aro-hcp/` |
| Gap analysis | [gap-analysis.md](gap-analysis.md) | — |
| Phase 1 report | [validation-report.md](validation-report.md) | — |

## Path A pass/fail matrix

Record results during live testing. Update [validation-report.md](validation-report.md) when complete.

| ID | Test | Procedure | Result | Date | Notes |
|----|------|-----------|--------|------|-------|
| PA-01 | Azure subscription has ARO HCP preview access | Confirm with PM / portal | | | |
| PA-02 | Cluster provisions to `Succeeded` | [02-provision-azure-cli.md](02-provision-azure-cli.md) | | | |
| PA-03 | API URL retrievable via ARM | `az rest` GET hcpOpenShiftClusters | | | |
| PA-04 | Admin kubeconfig issued | `request-aro-admin-credential.sh` | | | |
| PA-05 | `oc get clusteroperators` all Available | `./validate-cluster.sh` | | | |
| PA-06 | External auth Bicep deploys | [03-external-auth-rhbk.md](03-external-auth-rhbk.md) | | | |
| PA-07 | Console client secret created | Secret `{authName}-console-openshift-console` | | | |
| PA-08 | RBAC group binding works | `openshift_admins` → cluster-admin | | | |
| PA-09 | RHBK user logs into console | OIDC flow | | | |
| PA-10 | RHBK user `oc whoami` via token | [06-access RHAC](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/06-access.html) | | | |
| PA-11 | Admin credential re-issue after expiry | Re-run credential script | | | |

**Result values:** `PASS` | `FAIL` | `BLOCKED` | `PENDING`

## Day-2 smoke test matrix

| ID | Test | Bookbag source | Result | Notes |
|----|------|----------------|--------|-------|
| ST-01 | Worker scaling | `200-ops/day2/2-scaling-nodes` | | |
| ST-02 | Cluster autoscaling | `200-ops/day2/3-autoscaling` | | |
| ST-03 | Quarkus app deploy | `300-app/1-app-deploy` | | |
| ST-04 | OpenShift GitOps | `300-app/2-app-gitops` | | |
| ST-05 | Observability → Azure Files | `200-ops/day2/5-observability` | | |
| ST-06 | Service mesh | `500-service-mesh/*` | | Defer / BLOCKED expected |

Details: [05-smoke-tests.md](05-smoke-tests.md)

## Path B comparison matrix (terraform-aro-hcp)

| Capability | Classic ARO | Path A (Azure) | Path B (Terraform) |
|------------|-------------|----------------|---------------------|
| Provision API | `openShiftClusters` | `hcpOpenShiftClusters` | TBD — [06-terraform-aro-hcp.md](06-terraform-aro-hcp.md) |
| Default auth | kubeadmin + OAuth | External only | TBD |
| Admin access | `az aro list-credentials` | `requestAdminCredential` | TBD |
| IdP config | OAuth CR | Bicep `externalAuths` | TBD |

## References

- [RHAC — ARO HCP external auth](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/03-aro.html)
- [RHAC — Keycloak setup](https://www.redhat.com/architect/portfolio/detail/134-openshift-external-auth/05-keycloak.html)
- [Microsoft ARO documentation](https://learn.microsoft.com/en-us/azure/openshift/)
- [Azure/ARO-HCP upstream](https://github.com/Azure/ARO-HCP/)
- [Classic ARO workshop](https://github.com/rh-mobb/bookbag-aro-mobb)
- [ROSA HCP external auth (pattern reference)](../troubleshooting/ROSA/ROSA-HCP-External-auth.md)

## Troubleshooting

See [docs/troubleshooting/ARO/ARO-HCP-External-auth.md](../../troubleshooting/ARO/ARO-HCP-External-auth.md)
